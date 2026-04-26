import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { withFreshDb } from "../test-utils.js";
import {
  createDashboard,
  createDataSource,
  createWidget,
  seedPresetThemes,
  writeSnapshot,
} from "../db/repo.js";
import { buildHttpApp } from "./server.js";
import type { Hono } from "hono";

let cleanup: () => void = () => {};
let app: Hono;

beforeEach(() => {
  ({ cleanup } = withFreshDb());
  seedPresetThemes();
  app = buildHttpApp();
});

afterEach(() => {
  cleanup();
});

async function getJson(path: string): Promise<{ status: number; body: unknown }> {
  const res = await app.fetch(new Request(`http://localhost${path}`));
  const body = await res.json();
  return { status: res.status, body };
}

describe("HTTP server integration", () => {
  it("/health returns ok", async () => {
    const { status, body } = await getJson("/health");
    expect(status).toBe(200);
    expect(body).toMatchObject({ ok: true, service: "bentodeck" });
  });

  it("/dashboards returns an empty list by default", async () => {
    const { status, body } = await getJson("/dashboards");
    expect(status).toBe(200);
    expect(body).toEqual({ dashboards: [] });
  });

  it("/dashboards returns created dashboards", async () => {
    const d = createDashboard({ name: "Hello", themeId: "default" });
    const { body } = (await getJson("/dashboards")) as {
      body: { dashboards: Array<{ id: string; name: string }> };
    };
    expect(body.dashboards).toHaveLength(1);
    expect(body.dashboards[0]!.id).toBe(d.id);
    expect(body.dashboards[0]!.name).toBe("Hello");
  });

  it("/dashboards/:id returns dashboard + widgets", async () => {
    const d = createDashboard({ name: "Main", themeId: "default" });
    const s = createDataSource({
      name: "src",
      type: "rest",
      url: "https://example.com",
      method: "GET",
      pollIntervalSec: 60,
    });
    createWidget({
      dashboardId: d.id,
      sourceId: s.id,
      type: "number",
      title: "MRR",
      transformExpr: "mrr",
      position: 0,
    });

    const { status, body } = (await getJson(`/dashboards/${d.id}`)) as {
      status: number;
      body: { dashboard: { id: string }; widgets: Array<{ title: string }> };
    };
    expect(status).toBe(200);
    expect(body.dashboard.id).toBe(d.id);
    expect(body.widgets).toHaveLength(1);
    expect(body.widgets[0]!.title).toBe("MRR");
  });

  it("/dashboards/:id returns 404 when missing", async () => {
    const { status, body } = await getJson("/dashboards/nope");
    expect(status).toBe(404);
    expect(body).toEqual({ error: "not found" });
  });

  it("/dashboards/:id/snapshot includes latest snapshot values + theme", async () => {
    const d = createDashboard({ name: "Snap", themeId: "cyberpunk" });
    const s = createDataSource({
      name: "src",
      type: "rest",
      url: "https://example.com",
      method: "GET",
      pollIntervalSec: 60,
    });
    const w = createWidget({
      dashboardId: d.id,
      sourceId: s.id,
      type: "number",
      title: "Count",
      transformExpr: "count",
      position: 0,
    });
    writeSnapshot({ widgetId: w.id, value: 99 });

    const { status, body } = (await getJson(
      `/dashboards/${d.id}/snapshot`,
    )) as {
      status: number;
      body: {
        dashboardId: string;
        themeId: string;
        theme: { id: string } | null;
        widgets: Array<{
          id: string;
          value: unknown;
          anomaly: boolean;
          ts: string | null;
        }>;
      };
    };
    expect(status).toBe(200);
    expect(body.dashboardId).toBe(d.id);
    expect(body.themeId).toBe("cyberpunk");
    expect(body.theme?.id).toBe("cyberpunk");
    expect(body.widgets).toHaveLength(1);
    expect(body.widgets[0]!.id).toBe(w.id);
    expect(body.widgets[0]!.value).toBe(99);
    expect(body.widgets[0]!.anomaly).toBe(false);
    expect(body.widgets[0]!.ts).toBeTypeOf("string");
  });

  it("/dashboards/:id/snapshot exposes needsKey + sourceId per widget", async () => {
    const d = createDashboard({ name: "WithKey", themeId: "default" });
    const sNeeds = createDataSource({
      name: "vercel",
      type: "rest",
      url: "https://api.vercel.com/v6/deployments",
      method: "GET",
      authHeaderKey: "Authorization",
      authHeaderValue: "Bearer {{API_KEY}}",
      pollIntervalSec: 60,
      needsKey: true,
    });
    const sOk = createDataSource({
      name: "stripe",
      type: "rest",
      url: "https://example.com",
      method: "GET",
      pollIntervalSec: 60,
    });
    const wNeeds = createWidget({
      dashboardId: d.id,
      sourceId: sNeeds.id,
      type: "number",
      title: "Vercel deploys",
      transformExpr: "deployments[0].state",
      position: 0,
    });
    const wOk = createWidget({
      dashboardId: d.id,
      sourceId: sOk.id,
      type: "number",
      title: "MRR",
      transformExpr: "mrr",
      position: 1,
    });

    const { body } = (await getJson(`/dashboards/${d.id}/snapshot`)) as {
      body: {
        widgets: Array<{
          id: string;
          needsKey: boolean;
          sourceId: string;
          sourceName: string | null;
        }>;
      };
    };
    const byId = Object.fromEntries(body.widgets.map((w) => [w.id, w]));
    expect(byId[wNeeds.id]!.needsKey).toBe(true);
    expect(byId[wNeeds.id]!.sourceId).toBe(sNeeds.id);
    expect(byId[wNeeds.id]!.sourceName).toBe("vercel");
    expect(byId[wOk.id]!.needsKey).toBe(false);
    expect(byId[wOk.id]!.sourceId).toBe(sOk.id);
  });

  it("/dashboards/:id/snapshot falls back to default theme when theme missing", async () => {
    const d = createDashboard({
      name: "FallbackTheme",
      themeId: "nonexistent-theme",
    });
    const { body } = (await getJson(`/dashboards/${d.id}/snapshot`)) as {
      body: { theme: { id: string } | null };
    };
    expect(body.theme?.id).toBe("default");
  });

  it("/dashboards/:id/snapshot returns 404 when dashboard missing", async () => {
    const { status } = await getJson("/dashboards/missing/snapshot");
    expect(status).toBe(404);
  });

  it("/themes lists presets after seeding", async () => {
    const { body } = (await getJson("/themes")) as {
      body: { themes: Array<{ id: string }> };
    };
    const ids = body.themes.map((t) => t.id);
    expect(ids).toContain("default");
    expect(ids).toContain("cyberpunk");
    expect(ids).toContain("terminal");
    expect(ids).toContain("paper");
    expect(ids).toContain("bento-orange");
    expect(ids).toContain("pastel");
  });

  it("/themes/:id returns a specific theme", async () => {
    const { status, body } = (await getJson("/themes/terminal")) as {
      status: number;
      body: { theme: { id: string; name: string } };
    };
    expect(status).toBe(200);
    expect(body.theme.id).toBe("terminal");
    expect(body.theme.name).toBe("Terminal");
  });

  it("/themes/:id returns 404 when missing", async () => {
    const { status } = await getJson("/themes/nope");
    expect(status).toBe(404);
  });

  it("/demo/stripe/mrr is reachable through the mounted demo route", async () => {
    const { status, body } = (await getJson("/demo/stripe/mrr")) as {
      status: number;
      body: { object: string; currency: string };
    };
    expect(status).toBe(200);
    expect(body.object).toBe("summary");
    expect(body.currency).toBe("usd");
  });
});
