import jmespath from "jmespath";
import { evaluateAnomaly } from "../ai/anomaly.js";
import {
  latestSnapshot,
  listAllWidgets,
  listDataSources,
  markLatestSnapshotAnomaly,
  recentSnapshots,
  saveLastSample,
  writeSnapshot,
} from "../db/repo.js";
import { log } from "../logger.js";
import { fetchFromSource } from "../sources/fetch.js";
import type { DataSource, Widget } from "../types/schemas.js";
import { logGateDecision, shouldInvokeAnomalyAI } from "./anomaly-gate.js";

// Skip anomaly checks for the first N polls after process start, while the
// in-memory view of history is catching up with what's already in SQLite
// from a prior run. Prevents "startup-noise anomalies".
const WARMUP_POLLS_PER_WIDGET = 3;
const warmupCounts = new Map<string, number>();

// How often the poller wakes up to check what's due. Individual sources
// are polled at their own `pollIntervalSec`, which must be ≥ this tick.
const TICK_INTERVAL_MS = 5_000;

const lastPolledAt = new Map<string, number>();

async function pollSource(
  source: DataSource,
  widgets: Widget[],
): Promise<void> {
  try {
    const result = await fetchFromSource(source);
    if (!result.ok) {
      log.warn(
        `[poll] ${source.name} HTTP ${result.status} — ${result.bodyText.slice(0, 120)}`,
      );
      return;
    }
    saveLastSample(source.id, JSON.stringify(result.body));

    for (const widget of widgets) {
      try {
        const value = jmespath.search(
          result.body as object,
          widget.transformExpr,
        );

        // Persistence of anomaly state across unchanged-value polls.
        // If the value hasn't changed since the last snapshot, carry the
        // prior snapshot's anomaly flag + explanation forward. Without
        // this, a persistent spike (errors=47→47→47) looks "fine" to the
        // iOS app because each new row resets anomaly to 0, and the last-
        // snapshot query only sees the fresh row.
        const prev = latestSnapshot(widget.id);
        const unchanged =
          prev !== null &&
          JSON.stringify(prev.value) === JSON.stringify(value);
        if (unchanged && prev.anomalyFlag) {
          writeSnapshot({
            widgetId: widget.id,
            value,
            anomalyFlag: true,
            anomalyExplanation: prev.anomalyExplanation,
          });
        } else {
          writeSnapshot({ widgetId: widget.id, value });
          // Fire-and-forget anomaly check; don't block further widgets.
          // (The anomaly checker itself also short-circuits on unchanged
          // values; the outer condition is kept explicit for clarity.)
          if (!unchanged) void checkAnomalyForWidget(widget, value);
        }
      } catch (err) {
        log.warn(
          `[poll] transform failed widget=${widget.id} expr=${widget.transformExpr}`,
          err instanceof Error ? err.message : err,
        );
      }
    }
  } catch (err) {
    log.error(`[poll] fetch failed source=${source.id} name="${source.name}"`, err);
  }
}

async function tick(): Promise<void> {
  const now = Date.now();

  const sources = listDataSources();
  if (sources.length === 0) return;

  const widgets = listAllWidgets();
  const widgetsBySource = new Map<string, Widget[]>();
  for (const w of widgets) {
    const list = widgetsBySource.get(w.sourceId) ?? [];
    list.push(w);
    widgetsBySource.set(w.sourceId, list);
  }

  const tasks: Promise<void>[] = [];
  for (const source of sources) {
    const last = lastPolledAt.get(source.id) ?? 0;
    const dueAt = last + source.pollIntervalSec * 1000;
    if (now < dueAt) continue;

    const subscribers = widgetsBySource.get(source.id) ?? [];
    if (subscribers.length === 0) {
      // Nobody is listening — don't poll or spend budget.
      lastPolledAt.set(source.id, now);
      continue;
    }

    lastPolledAt.set(source.id, now);
    tasks.push(pollSource(source, subscribers));
  }

  if (tasks.length > 0) {
    await Promise.allSettled(tasks);
  }
}

async function checkAnomalyForWidget(
  widget: Widget,
  currentValue: unknown,
): Promise<void> {
  try {
    // Warmup: ignore anomaly checks for the first N polls of a widget's
    // process lifetime. Avoids spurious "startup anomalies" from a
    // cold-started server seeing old SQLite history.
    const warmup = warmupCounts.get(widget.id) ?? 0;
    if (warmup < WARMUP_POLLS_PER_WIDGET) {
      warmupCounts.set(widget.id, warmup + 1);
      return;
    }

    // Pull a window that includes the just-written snapshot; the latest entry
    // corresponds to currentValue, the rest are prior history.
    const recent = recentSnapshots(widget.id, 20);
    if (recent.length < 4) return; // need >= 3 priors for a meaningful signal

    const priorEntries = recent.slice(1);
    const prevValue = priorEntries[0]?.value;
    // Skip check if the value didn't change — saves model quota on idle polls.
    if (JSON.stringify(prevValue) === JSON.stringify(currentValue)) return;

    const history = priorEntries
      .slice()
      .reverse()
      .map((s) => ({ value: s.value, ts: s.ts }));

    // Cost-control gate: statistical pre-filter + per-widget daily cap.
    // Only calls Opus 4.7 when the current value is meaningfully outside
    // normal noise AND the widget hasn't burned its daily AI budget.
    const gate = shouldInvokeAnomalyAI({
      widgetId: widget.id,
      widgetTitle: widget.title,
      history: history.map((h) => ({ value: h.value })),
      currentValue,
    });
    logGateDecision(widget.id, widget.title, gate);
    if (!gate.proceed) return;

    const result = await evaluateAnomaly({
      widget,
      history,
      currentValue,
    });
    if (result.isAnomaly) {
      markLatestSnapshotAnomaly(widget.id, true, result.explanation);
      log.info(
        `[anomaly] widget=${widget.id} title="${widget.title}" — ${result.explanation}`,
      );
    }
  } catch (err) {
    log.warn(
      `[anomaly] widget=${widget.id} evaluation failed`,
      err instanceof Error ? err.message : err,
    );
  }
}

let handle: NodeJS.Timeout | null = null;

export function startPoller(): () => void {
  if (handle) return stopPoller;
  const run = () =>
    tick().catch((err) => log.error("[poll] tick failed", err));
  handle = setInterval(run, TICK_INTERVAL_MS);
  // Kick one off immediately so first widget snapshots don't wait a full tick.
  run();
  log.info(`Poll scheduler running (tick=${TICK_INTERVAL_MS}ms)`);
  return stopPoller;
}

export function stopPoller(): void {
  if (handle) {
    clearInterval(handle);
    handle = null;
    log.info("Poll scheduler stopped");
  }
}

// Test-only hook: run a single deterministic tick and await completion.
export async function tickOnce(): Promise<void> {
  await tick();
}

// Test-only hook: clear scheduler memory between test cases.
export function __resetPollerForTests(): void {
  lastPolledAt.clear();
  warmupCounts.clear();
}
