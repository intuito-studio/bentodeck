import jmespath from "jmespath";
import { evaluateAnomaly } from "../ai/anomaly.js";
import {
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
        writeSnapshot({ widgetId: widget.id, value });
        // Fire-and-forget anomaly check; don't block further widgets.
        void checkAnomalyForWidget(widget, value);
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
}
