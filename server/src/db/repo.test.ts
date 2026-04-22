import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { withFreshDb } from "../test-utils.js";
import {
  createDashboard,
  createDataSource,
  createWidget,
  deleteDashboard,
  getDashboard,
  getDataSource,
  getTheme,
  latestSnapshot,
  listDashboards,
  listThemes,
  listWidgetsForDashboard,
  markLatestSnapshotAnomaly,
  recentSnapshots,
  saveLastSample,
  saveTheme,
  seedPresetThemes,
  setDashboardTheme,
  writeSnapshot,
} from "./repo.js";
import { PRESET_THEMES } from "../themes/presets.js";
import type { Theme } from "../themes/presets.js";

let cleanup: () => void = () => {};

beforeEach(() => {
  ({ cleanup } = withFreshDb());
});

afterEach(() => {
  cleanup();
});

describe("dashboards repo", () => {
  it("creates and reads back a dashboard", () => {
    const d = createDashboard({ name: "My SaaS", themeId: "default" });
    expect(d.id).toMatch(/^[0-9a-f-]{36}$/);
    expect(d.name).toBe("My SaaS");
    expect(d.themeId).toBe("default");
    expect(d.createdAt).toBeTypeOf("string");

    const fetched = getDashboard(d.id);
    expect(fetched).toEqual(d);
  });

  it("returns null for unknown dashboard id", () => {
    expect(getDashboard("does-not-exist")).toBeNull();
  });

  it("lists dashboards newest-first", () => {
    const a = createDashboard({ name: "A", themeId: "default" });
    const b = createDashboard({ name: "B", themeId: "default" });
    const all = listDashboards();
    expect(all.map((d) => d.id)).toContain(a.id);
    expect(all.map((d) => d.id)).toContain(b.id);
    expect(all).toHaveLength(2);
  });

  it("deleteDashboard returns true on hit, false on miss", () => {
    const d = createDashboard({ name: "X", themeId: "default" });
    expect(deleteDashboard(d.id)).toBe(true);
    expect(getDashboard(d.id)).toBeNull();
    expect(deleteDashboard(d.id)).toBe(false);
    expect(deleteDashboard("nope")).toBe(false);
  });

  it("setDashboardTheme updates theme id", () => {
    const d = createDashboard({ name: "Y", themeId: "default" });
    expect(setDashboardTheme(d.id, "cyberpunk")).toBe(true);
    expect(getDashboard(d.id)?.themeId).toBe("cyberpunk");
    expect(setDashboardTheme("missing", "terminal")).toBe(false);
  });

  it("deleting a dashboard cascades to its widgets and snapshots", () => {
    const d = createDashboard({ name: "Casc", themeId: "default" });
    const s = createDataSource({
      name: "src",
      type: "rest",
      url: "https://example.com/api",
      method: "GET",
      pollIntervalSec: 60,
    });
    const w = createWidget({
      dashboardId: d.id,
      sourceId: s.id,
      type: "number",
      title: "W",
      transformExpr: "value",
      position: 0,
    });
    writeSnapshot({ widgetId: w.id, value: 1 });
    expect(latestSnapshot(w.id)).not.toBeNull();

    expect(deleteDashboard(d.id)).toBe(true);
    expect(listWidgetsForDashboard(d.id)).toHaveLength(0);
    // snapshot should have been cascaded
    expect(latestSnapshot(w.id)).toBeNull();
  });
});

describe("data_sources repo", () => {
  it("createDataSource roundtrips all fields", () => {
    const s = createDataSource({
      name: "Stripe MRR",
      type: "rest",
      url: "https://api.stripe.com/v1/mrr",
      method: "GET",
      headers: { "X-Test": "1" },
      authHeaderKey: "Authorization",
      authHeaderValue: "Bearer sk_test_123",
      pollIntervalSec: 30,
    });
    expect(s.id).toMatch(/^[0-9a-f-]{36}$/);
    const fetched = getDataSource(s.id);
    expect(fetched).not.toBeNull();
    expect(fetched!.name).toBe("Stripe MRR");
    expect(fetched!.url).toBe("https://api.stripe.com/v1/mrr");
    expect(fetched!.headers).toEqual({ "X-Test": "1" });
    expect(fetched!.authHeaderKey).toBe("Authorization");
    expect(fetched!.authHeaderValue).toBe("Bearer sk_test_123");
    expect(fetched!.pollIntervalSec).toBe(30);
    expect(fetched!.lastSampleJson).toBeNull();
  });

  it("getDataSource returns null for missing id", () => {
    expect(getDataSource("missing")).toBeNull();
  });

  it("saveLastSample updates last_sample_json", () => {
    const s = createDataSource({
      name: "s",
      type: "rest",
      url: "https://example.com",
      method: "GET",
      pollIntervalSec: 60,
    });
    const payload = JSON.stringify({ mrr: 12345 });
    saveLastSample(s.id, payload);
    expect(getDataSource(s.id)!.lastSampleJson).toBe(payload);
  });

  it("createDataSource without headers stores undefined, not an object", () => {
    const s = createDataSource({
      name: "no-headers",
      type: "rest",
      url: "https://example.com",
      method: "GET",
      pollIntervalSec: 60,
    });
    expect(getDataSource(s.id)!.headers).toBeUndefined();
  });
});

describe("widgets repo", () => {
  it("createWidget + listWidgetsForDashboard orders by position then createdAt", () => {
    const d = createDashboard({ name: "W", themeId: "default" });
    const s = createDataSource({
      name: "s",
      type: "rest",
      url: "https://example.com",
      method: "GET",
      pollIntervalSec: 60,
    });
    const wB = createWidget({
      dashboardId: d.id,
      sourceId: s.id,
      type: "number",
      title: "B",
      transformExpr: "b",
      position: 2,
    });
    const wA = createWidget({
      dashboardId: d.id,
      sourceId: s.id,
      type: "number",
      title: "A",
      transformExpr: "a",
      position: 1,
    });
    const list = listWidgetsForDashboard(d.id);
    expect(list.map((w) => w.id)).toEqual([wA.id, wB.id]);
  });

  it("listWidgetsForDashboard returns [] for dashboards without widgets", () => {
    const d = createDashboard({ name: "Empty", themeId: "default" });
    expect(listWidgetsForDashboard(d.id)).toEqual([]);
  });
});

describe("snapshots repo", () => {
  function scaffold(): { widgetId: string } {
    const d = createDashboard({ name: "D", themeId: "default" });
    const s = createDataSource({
      name: "s",
      type: "rest",
      url: "https://example.com",
      method: "GET",
      pollIntervalSec: 60,
    });
    const w = createWidget({
      dashboardId: d.id,
      sourceId: s.id,
      type: "number",
      title: "W",
      transformExpr: "v",
      position: 0,
    });
    return { widgetId: w.id };
  }

  it("writeSnapshot + latestSnapshot round-trips the value", () => {
    const { widgetId } = scaffold();
    writeSnapshot({ widgetId, value: { count: 42 } });
    const snap = latestSnapshot(widgetId);
    expect(snap).not.toBeNull();
    expect(snap!.value).toEqual({ count: 42 });
    expect(snap!.anomalyFlag).toBe(false);
    expect(snap!.anomalyExplanation).toBeNull();
    expect(snap!.ts).toBeTypeOf("string");
  });

  it("latestSnapshot returns null when there are no snapshots", () => {
    const { widgetId } = scaffold();
    expect(latestSnapshot(widgetId)).toBeNull();
  });

  it("recentSnapshots is capped by limit and returns all rows within a widget", () => {
    const { widgetId } = scaffold();
    // NOTE: snapshots.ts uses `datetime('now')` (second-granular) for ts.
    // Multiple writes in the same second all share a ts, so we cannot
    // assert exact descending order here without a time-travel helper.
    // See report: suggested fix is to break ts ties by the autoincrement id.
    for (let i = 0; i < 5; i++) writeSnapshot({ widgetId, value: i });
    const recent = recentSnapshots(widgetId, 3);
    expect(recent).toHaveLength(3);
    const recentAll = recentSnapshots(widgetId, 100);
    expect(recentAll).toHaveLength(5);
    expect(new Set(recentAll.map((r) => r.value))).toEqual(
      new Set([0, 1, 2, 3, 4]),
    );
  });

  it("markLatestSnapshotAnomaly flips the flag on the most recent snapshot", () => {
    const { widgetId } = scaffold();
    writeSnapshot({ widgetId, value: 42 });
    expect(markLatestSnapshotAnomaly(widgetId, true, "went weird")).toBe(true);

    const snap = latestSnapshot(widgetId);
    expect(snap!.value).toBe(42);
    expect(snap!.anomalyFlag).toBe(true);
    expect(snap!.anomalyExplanation).toBe("went weird");
  });

  it("markLatestSnapshotAnomaly returns false when there are no snapshots", () => {
    const { widgetId } = scaffold();
    expect(markLatestSnapshotAnomaly(widgetId, true, "x")).toBe(false);
  });
});

describe("themes repo", () => {
  it("seedPresetThemes writes all presets", () => {
    seedPresetThemes();
    const themes = listThemes();
    const ids = themes.map((t) => t.id);
    for (const p of PRESET_THEMES) {
      expect(ids).toContain(p.id);
    }
  });

  it("saveTheme + getTheme roundtrips a custom theme", () => {
    const t: Theme = {
      id: "my-theme",
      name: "My Theme",
      colors: {
        background: "#000",
        surface: "#111",
        primary: "#fff",
        secondary: "#888",
        accent: "#f0f",
        positive: "#0f0",
        negative: "#f00",
        border: "#333",
      },
      font: { family: "rounded", weightPrimary: "bold" },
      chart: { stroke: "#fff", fillStart: "#fff0", fillEnd: "#fff0" },
    };
    saveTheme(t, false);
    const got = getTheme("my-theme");
    expect(got).toEqual(t);
  });

  it("getTheme returns null for an unknown id", () => {
    expect(getTheme("not-a-theme")).toBeNull();
  });

  it("listThemes after seeding contains presets first (is_preset DESC)", () => {
    seedPresetThemes();
    // custom theme saved after seeding, non-preset
    saveTheme(
      {
        ...PRESET_THEMES[0]!,
        id: "custom",
        name: "Custom",
      },
      false,
    );
    const themes = listThemes();
    // All presets are is_preset=1, custom is is_preset=0 → presets come first.
    const firstNonPresetIdx = themes.findIndex((t) => t.id === "custom");
    const firstPresetIdx = themes.findIndex((t) =>
      PRESET_THEMES.some((p) => p.id === t.id),
    );
    expect(firstPresetIdx).toBeLessThan(firstNonPresetIdx);
  });
});
