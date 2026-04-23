import { afterEach, describe, expect, it } from "vitest";
import {
  __resetAnomalyGateForTests,
  shouldInvokeAnomalyAI,
} from "./anomaly-gate.js";

afterEach(() => {
  __resetAnomalyGateForTests();
});

function flatHistory(values: number[]): Array<{ value: unknown }> {
  return values.map((v) => ({ value: v }));
}

describe("anomaly-gate: statistical pre-filter", () => {
  it("skips when current value is within normal noise", () => {
    const d = shouldInvokeAnomalyAI({
      widgetId: "w1",
      widgetTitle: "MRR",
      history: flatHistory([4280, 4281, 4283, 4284, 4285, 4286, 4287]),
      currentValue: 4288,
    });
    expect(d.proceed).toBe(false);
    expect(d.reason).toContain("stat-gate");
  });

  it("proceeds when current value is a clear outlier (high z)", () => {
    const d = shouldInvokeAnomalyAI({
      widgetId: "w2",
      widgetTitle: "Errors",
      history: flatHistory([0, 0, 0, 0, 0, 0, 0, 0]),
      currentValue: 47,
    });
    expect(d.proceed).toBe(true);
  });

  it("proceeds when series is perfectly flat but current differs", () => {
    const d = shouldInvokeAnomalyAI({
      widgetId: "w3",
      widgetTitle: "Errors",
      history: flatHistory([0, 0, 0, 0, 0]),
      currentValue: 1,
    });
    expect(d.proceed).toBe(true);
  });

  it("proceeds when we don't have enough history for stats (non-numeric)", () => {
    const d = shouldInvokeAnomalyAI({
      widgetId: "w4",
      widgetTitle: "Status",
      history: [{ value: "ok" }, { value: "ok" }, { value: "ok" }],
      currentValue: "error",
    });
    expect(d.proceed).toBe(true);
  });

  it("skips when current matches a slow upward trend within variance", () => {
    // Deliberately-noisy upward drift; value of 4290 falls comfortably inside
    // the rolling noise band.
    const d = shouldInvokeAnomalyAI({
      widgetId: "w5",
      widgetTitle: "MRR",
      history: flatHistory([4280, 4283, 4285, 4286, 4289, 4291, 4292]),
      currentValue: 4290,
    });
    expect(d.proceed).toBe(false);
  });
});

describe("anomaly-gate: per-widget daily cap", () => {
  it("enforces the daily cap", () => {
    const opts = {
      widgetId: "w-cap",
      widgetTitle: "Errors",
      history: flatHistory([0, 0, 0, 0, 0]),
      currentValue: 47,
    };
    // First 20 calls pass (the current default cap)
    for (let i = 0; i < 20; i++) {
      expect(shouldInvokeAnomalyAI(opts).proceed).toBe(true);
    }
    // The 21st is blocked by the cap
    const d = shouldInvokeAnomalyAI(opts);
    expect(d.proceed).toBe(false);
    expect(d.reason).toContain("daily-cap");
  });

  it("does not record a call when the statistical filter rejects", () => {
    const benign = {
      widgetId: "w-benign",
      widgetTitle: "MRR",
      history: flatHistory([4280, 4281, 4283, 4284, 4285, 4286, 4287]),
      currentValue: 4288,
    };
    // Spam the benign case 100 times — never counts against the cap.
    for (let i = 0; i < 100; i++) {
      expect(shouldInvokeAnomalyAI(benign).proceed).toBe(false);
    }
    // A genuine spike for the same widget still has its full budget.
    const spike = {
      ...benign,
      currentValue: 99999,
    };
    expect(shouldInvokeAnomalyAI(spike).proceed).toBe(true);
  });

  it("tracks caps independently per widget", () => {
    const history = flatHistory([0, 0, 0, 0, 0]);
    const a = { widgetId: "w-a", widgetTitle: "A", history, currentValue: 47 };
    const b = { widgetId: "w-b", widgetTitle: "B", history, currentValue: 47 };
    for (let i = 0; i < 20; i++) shouldInvokeAnomalyAI(a);
    expect(shouldInvokeAnomalyAI(a).proceed).toBe(false);
    // Widget B is unaffected.
    expect(shouldInvokeAnomalyAI(b).proceed).toBe(true);
  });
});
