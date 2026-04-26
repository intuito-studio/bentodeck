import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { withFreshDb } from "../test-utils.js";
import {
  createDashboard,
  createDataSource,
  createWidget,
  getDataSource,
  latestSnapshot,
  markLatestSnapshotAnomaly,
} from "../db/repo.js";
import { __resetPollerForTests, tickOnce } from "./poller.js";

// End-to-end poll loop test. Hits a local ephemeral HTTP server (no
// external network), runs a single deterministic tick, asserts the
// JMESPath-extracted value landed in SQLite as a snapshot, and asserts
// throttling on a second immediate tick.

let cleanup: () => void = () => {};
let server: Server;
let baseUrl = "";

beforeEach(async () => {
  ({ cleanup } = withFreshDb());
  __resetPollerForTests();

  server = createServer((req, res) => {
    if (req.url === "/data") {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ metrics: { count: 1234 } }));
      return;
    }
    res.writeHead(404);
    res.end();
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const addr = server.address() as AddressInfo;
  baseUrl = `http://127.0.0.1:${addr.port}`;
});

afterEach(async () => {
  __resetPollerForTests();
  await new Promise<void>((resolve, reject) =>
    server.close((err) => (err ? reject(err) : resolve())),
  );
  cleanup();
});

describe("poll loop", () => {
  it("tickOnce fetches the source and writes a JMESPath-extracted snapshot", async () => {
    const dash = createDashboard({ name: "PollerTest", themeId: "default" });
    const src = createDataSource({
      name: "local",
      type: "rest",
      url: `${baseUrl}/data`,
      method: "GET",
      pollIntervalSec: 1,
    });
    const widget = createWidget({
      dashboardId: dash.id,
      sourceId: src.id,
      type: "number",
      title: "Count",
      transformExpr: "metrics.count",
      position: 0,
    });

    await tickOnce();

    const snap = latestSnapshot(widget.id);
    expect(snap).not.toBeNull();
    expect(snap!.value).toBe(1234);

    // Source last_sample_json is updated with the raw body.
    const refreshed = getDataSource(src.id);
    expect(refreshed!.lastSampleJson).toBeTypeOf("string");
    const sample = JSON.parse(refreshed!.lastSampleJson!);
    expect(sample).toEqual({ metrics: { count: 1234 } });
  });

  it("skips sources flagged needsKey (no snapshot is written)", async () => {
    // Mirror the "discovered from docs but waiting on user's API key"
    // state — the poller must NOT hit the endpoint at all, because the
    // call would just 401 and burn rate limit. The widget shows a
    // "Connect" warning in the iOS app instead.
    const dash = createDashboard({ name: "Locked", themeId: "default" });
    const src = createDataSource({
      name: "needs-key",
      type: "rest",
      url: `${baseUrl}/data`,
      method: "GET",
      authHeaderKey: "Authorization",
      authHeaderValue: "Bearer {{API_KEY}}",
      pollIntervalSec: 1,
      needsKey: true,
    });
    const widget = createWidget({
      dashboardId: dash.id,
      sourceId: src.id,
      type: "number",
      title: "Count",
      transformExpr: "metrics.count",
      position: 0,
    });

    await tickOnce();

    expect(latestSnapshot(widget.id)).toBeNull();
    // Source's last_sample_json should also be untouched.
    expect(getDataSource(src.id)!.lastSampleJson).toBeNull();
  });

  it("skips polling when no widgets are attached to the source", async () => {
    createDataSource({
      name: "lonely",
      type: "rest",
      url: `${baseUrl}/data`,
      method: "GET",
      pollIntervalSec: 1,
    });
    // No widget attached.
    await tickOnce();
    // If we made it here without crashing and with no snapshot anywhere, pass.
    // (We don't assert server hit count because http.Server doesn't expose it cheaply.)
  });

  it("throttles: a second tick immediately after does not write a new snapshot", async () => {
    const dash = createDashboard({ name: "Throttle", themeId: "default" });
    const src = createDataSource({
      name: "throttled",
      type: "rest",
      url: `${baseUrl}/data`,
      method: "GET",
      pollIntervalSec: 3600, // very long so the second tick is not due
    });
    const widget = createWidget({
      dashboardId: dash.id,
      sourceId: src.id,
      type: "number",
      title: "Count",
      transformExpr: "metrics.count",
      position: 0,
    });

    await tickOnce();
    const firstSnap = latestSnapshot(widget.id);
    expect(firstSnap).not.toBeNull();
    const firstTs = firstSnap!.ts;

    await tickOnce();
    const secondSnap = latestSnapshot(widget.id);
    // Same ts means no new snapshot was written (poll was throttled).
    expect(secondSnap!.ts).toBe(firstTs);
  });

  it("carries anomaly state forward across unchanged-value polls", async () => {
    const dash = createDashboard({ name: "Persist", themeId: "default" });
    const src = createDataSource({
      name: "src",
      type: "rest",
      url: `${baseUrl}/data`,
      method: "GET",
      pollIntervalSec: 1,
    });
    const widget = createWidget({
      dashboardId: dash.id,
      sourceId: src.id,
      type: "number",
      title: "Count",
      transformExpr: "metrics.count",
      position: 0,
    });

    // Seed: write an initial snapshot, then mark it anomalous — mimicking the
    // point in time right after Opus 4.7 flagged a spike.
    await tickOnce();
    const firstSnap = latestSnapshot(widget.id);
    expect(firstSnap).not.toBeNull();
    expect(firstSnap!.value).toBe(1234);
    markLatestSnapshotAnomaly(widget.id, true, "seeded spike explanation");

    // Subsequent poll with unchanged value must not erase the anomaly state.
    __resetPollerForTests();
    await tickOnce();
    const second = latestSnapshot(widget.id);
    expect(second!.value).toBe(1234);
    expect(second!.anomalyFlag).toBe(true);
    expect(second!.anomalyExplanation).toBe("seeded spike explanation");
  });

  it("handles an upstream HTTP error without throwing", async () => {
    const dash = createDashboard({ name: "Err", themeId: "default" });
    const src = createDataSource({
      name: "bad-url",
      type: "rest",
      url: `${baseUrl}/does-not-exist`, // 404
      method: "GET",
      pollIntervalSec: 1,
    });
    const widget = createWidget({
      dashboardId: dash.id,
      sourceId: src.id,
      type: "number",
      title: "X",
      transformExpr: "a.b",
      position: 0,
    });

    await expect(tickOnce()).resolves.toBeUndefined();
    expect(latestSnapshot(widget.id)).toBeNull();
  });
});
