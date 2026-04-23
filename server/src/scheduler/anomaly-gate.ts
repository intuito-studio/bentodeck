import { log } from "../logger.js";

/**
 * Cost-control gate for Opus 4.7 anomaly-detection calls.
 *
 * A naive "call Opus on every change" design burns real money at scale
 * (≈$0.012 per call × however many polls × however many widgets × however
 * many users). This module gates those calls behind two cheap filters
 * before any AI spend:
 *
 *   1. **Statistical pre-filter.** Compute z-score of the current value
 *      against the rolling mean/stdev of recent history. If the current
 *      value is within normal noise (|z| < Z_THRESHOLD), skip AI.
 *      Handles the common case: values drift slightly, nothing is wrong.
 *
 *   2. **Per-widget daily cap.** Track AI calls per widget in a sliding
 *      24h window. If a widget has already spent its daily budget, skip
 *      — even if the pre-filter flagged it. Prevents runaway cost from a
 *      widget that genuinely is noisy.
 *
 * Only when both filters pass does the caller invoke Opus 4.7.
 *
 * Non-numeric widgets (list/status) bypass the statistical filter — they
 * still get checked if the value changed, subject to the daily cap.
 */

const Z_THRESHOLD = 2.5;
const MIN_HISTORY_FOR_STATS = 5;
// Generous default so the hackathon demo + rehearsals never hit the cap.
// Post-hackathon SaaS will probably drop this to 5-10 on free tier.
const MAX_AI_CALLS_PER_WIDGET_PER_DAY = 20;
const WINDOW_MS = 24 * 60 * 60 * 1000;

// Per-widget sliding window of AI-call timestamps (ms).
const callHistory = new Map<string, number[]>();

function toNumber(v: unknown): number | null {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string") {
    const n = Number(v);
    return Number.isFinite(n) ? n : null;
  }
  if (typeof v === "boolean") return v ? 1 : 0;
  return null;
}

function zScore(history: number[], current: number): number | null {
  if (history.length < MIN_HISTORY_FOR_STATS) return null;
  const mean = history.reduce((s, v) => s + v, 0) / history.length;
  const variance =
    history.reduce((s, v) => s + (v - mean) ** 2, 0) / history.length;
  const stdev = Math.sqrt(variance);
  if (stdev === 0) {
    // Perfectly flat series; any deviation is "infinite" z. Treat as high.
    return current === mean ? 0 : Number.POSITIVE_INFINITY;
  }
  return Math.abs(current - mean) / stdev;
}

export type GateDecision =
  | { proceed: true; reason: string }
  | { proceed: false; reason: string };

export function shouldInvokeAnomalyAI(args: {
  widgetId: string;
  widgetTitle: string;
  history: Array<{ value: unknown }>;
  currentValue: unknown;
}): GateDecision {
  const { widgetId, widgetTitle, history, currentValue } = args;

  // --- Statistical pre-filter ---------------------------------------------
  const priorNumbers = history
    .map((h) => toNumber(h.value))
    .filter((n): n is number => n !== null);
  const current = toNumber(currentValue);

  if (priorNumbers.length >= MIN_HISTORY_FOR_STATS && current !== null) {
    const z = zScore(priorNumbers, current);
    if (z !== null && z < Z_THRESHOLD) {
      return {
        proceed: false,
        reason: `stat-gate: z=${z.toFixed(2)} < ${Z_THRESHOLD} (within noise)`,
      };
    }
  }
  // Non-numeric widgets: skip the statistical test; caller already
  // ensured the value changed before invoking us.

  // --- Per-widget daily cap -----------------------------------------------
  const now = Date.now();
  const historyTimestamps = (callHistory.get(widgetId) ?? []).filter(
    (ts) => now - ts < WINDOW_MS,
  );
  if (historyTimestamps.length >= MAX_AI_CALLS_PER_WIDGET_PER_DAY) {
    callHistory.set(widgetId, historyTimestamps); // prune stale
    return {
      proceed: false,
      reason: `daily-cap: widget="${widgetTitle}" already used ${historyTimestamps.length}/${MAX_AI_CALLS_PER_WIDGET_PER_DAY} today`,
    };
  }

  // Record this call now — we're about to proceed.
  historyTimestamps.push(now);
  callHistory.set(widgetId, historyTimestamps);

  const zTxt = (() => {
    if (priorNumbers.length < MIN_HISTORY_FOR_STATS || current === null) {
      return "no-stats";
    }
    const z = zScore(priorNumbers, current);
    return z === null ? "no-stats" : `z=${z.toFixed(2)}`;
  })();

  return {
    proceed: true,
    reason: `gate-pass: ${zTxt}, daily=${historyTimestamps.length}/${MAX_AI_CALLS_PER_WIDGET_PER_DAY}`,
  };
}

export function __resetAnomalyGateForTests(): void {
  callHistory.clear();
}

export function logGateDecision(
  widgetId: string,
  widgetTitle: string,
  decision: GateDecision,
): void {
  if (decision.proceed) {
    log.debug(`[anomaly-gate] widget=${widgetId} title="${widgetTitle}" ${decision.reason}`);
  } else {
    log.debug(`[anomaly-gate] SKIP widget=${widgetId} title="${widgetTitle}" ${decision.reason}`);
  }
}
