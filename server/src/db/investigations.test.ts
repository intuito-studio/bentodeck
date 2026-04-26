import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { withFreshDb } from "../test-utils.js";
import {
  createDashboard,
  createDataSource,
  createInvestigation,
  createWidget,
  getInvestigation,
  kvGet,
  kvSet,
  listInvestigationsForWidget,
  updateInvestigation,
  writeSnapshot,
} from "./repo.js";

let cleanup: () => void = () => {};
let widgetId = "";

beforeEach(() => {
  ({ cleanup } = withFreshDb());
  const dash = createDashboard({ name: "D", themeId: "default" });
  const src = createDataSource({
    name: "S",
    type: "rest",
    url: "http://example.com",
    method: "GET",
    pollIntervalSec: 60,
  });
  const w = createWidget({
    dashboardId: dash.id,
    sourceId: src.id,
    type: "number",
    title: "Errors",
    transformExpr: "x",
    position: 0,
  });
  widgetId = w.id;
});

afterEach(() => {
  cleanup();
});

describe("kv table", () => {
  it("returns null for unset keys", () => {
    expect(kvGet("missing")).toBeNull();
  });

  it("set then get round-trips a value", () => {
    kvSet("agent_id", "ag_abc");
    expect(kvGet("agent_id")).toBe("ag_abc");
  });

  it("set overwrites existing value (UPSERT)", () => {
    kvSet("agent_id", "v1");
    kvSet("agent_id", "v2");
    expect(kvGet("agent_id")).toBe("v2");
  });
});

describe("investigations", () => {
  it("creates with status=pending and no report", () => {
    const inv = createInvestigation({ id: "inv-1", widgetId });
    expect(inv.status).toBe("pending");
    expect(inv.report).toBeNull();
    expect(inv.error).toBeNull();
    expect(inv.completedAt).toBeNull();
  });

  it("attaches a snapshot id when provided", () => {
    writeSnapshot({ widgetId, value: 42 });
    createInvestigation({ id: "inv-2", widgetId, snapshotId: 1 });
    const found = getInvestigation("inv-2");
    expect(found?.snapshotId).toBe(1);
  });

  it("updates status, report, sessionId atomically", () => {
    createInvestigation({ id: "inv-3", widgetId });
    updateInvestigation("inv-3", {
      status: "running",
      sessionId: "ses_xyz",
    });
    let inv = getInvestigation("inv-3");
    expect(inv?.status).toBe("running");
    expect(inv?.sessionId).toBe("ses_xyz");

    updateInvestigation("inv-3", {
      status: "done",
      report: "## Headline\n\nBody.",
      title: "Headline",
    });
    inv = getInvestigation("inv-3");
    expect(inv?.status).toBe("done");
    expect(inv?.report).toContain("Headline");
    expect(inv?.title).toBe("Headline");
    expect(inv?.completedAt).not.toBeNull();
  });

  it("records error and completed_at on failure", () => {
    createInvestigation({ id: "inv-4", widgetId });
    updateInvestigation("inv-4", {
      status: "failed",
      error: "boom",
    });
    const inv = getInvestigation("inv-4");
    expect(inv?.status).toBe("failed");
    expect(inv?.error).toBe("boom");
    expect(inv?.completedAt).not.toBeNull();
  });

  it("listInvestigationsForWidget returns most recent first", async () => {
    createInvestigation({ id: "a", widgetId });
    // Force distinct datetime() values: SQLite datetime('now') has 1s
    // resolution so a tiny sleep guarantees ordering.
    await new Promise((r) => setTimeout(r, 1100));
    createInvestigation({ id: "b", widgetId });
    const list = listInvestigationsForWidget(widgetId);
    expect(list.map((i) => i.id)).toEqual(["b", "a"]);
  });

  it("updateInvestigation with no fields is a no-op", () => {
    createInvestigation({ id: "noop", widgetId });
    const before = getInvestigation("noop")!;
    updateInvestigation("noop", {});
    const after = getInvestigation("noop")!;
    expect(after).toEqual(before);
  });
});
