import { serve } from "@hono/node-server";
import { Hono } from "hono";
import {
  getDashboard,
  getTheme,
  latestSnapshot,
  listDashboards,
  listInvestigationsForWidget,
  listThemes,
  listWidgetsForDashboard,
  recentSnapshots,
} from "../db/repo.js";
import { createMockApi } from "../demo/mock-api.js";
import { log } from "../logger.js";
import { buildRoutes } from "./routes.js";

const PORT = Number(process.env.BENTODECK_HTTP_PORT ?? 3737);

// Builds the configured Hono app without binding a port. Exported so tests
// can exercise routes via `app.fetch(new Request(...))`.
export function buildHttpApp(): Hono {
  const app = new Hono();

  // CORS for the iOS simulator (harmless on device)
  app.use("*", async (c, next) => {
    c.header("Access-Control-Allow-Origin", "*");
    c.header("Access-Control-Allow-Methods", "GET, OPTIONS");
    c.header("Access-Control-Allow-Headers", "Content-Type");
    if (c.req.method === "OPTIONS") return c.body(null, 204);
    await next();
  });

  app.get("/health", (c) =>
    c.json({ ok: true, service: "bentodeck", version: "0.1.0" }),
  );

  app.get("/dashboards", (c) => {
    return c.json({ dashboards: listDashboards() });
  });

  app.get("/dashboards/:id", (c) => {
    const dash = getDashboard(c.req.param("id"));
    if (!dash) return c.json({ error: "not found" }, 404);
    const widgets = listWidgetsForDashboard(dash.id);
    return c.json({ dashboard: dash, widgets });
  });

  app.get("/dashboards/:id/snapshot", (c) => {
    const dashboardId = c.req.param("id");
    const dash = getDashboard(dashboardId);
    if (!dash) return c.json({ error: "not found" }, 404);

    const widgets = listWidgetsForDashboard(dashboardId).map((w) => {
      const snap = latestSnapshot(w.id);
      // Trailing numeric history so iOS can render sparklines + trend arrows.
      // Cheap query (indexed by widget_id+ts), capped at 24 points.
      const recent = recentSnapshots(w.id, 24);
      const numericHistory: number[] = [];
      // recent is newest→oldest; reverse for chronological order.
      for (const s of recent.slice().reverse()) {
        if (typeof s.value === "number" && Number.isFinite(s.value)) {
          numericHistory.push(s.value);
        } else if (typeof s.value === "string") {
          const n = Number(s.value);
          if (Number.isFinite(n)) numericHistory.push(n);
        }
      }
      // Quick "is there a still-pending or recent investigation?" hint.
      const investigations = listInvestigationsForWidget(w.id, 1);
      const investigation = investigations[0] ?? null;
      return {
        id: w.id,
        title: w.title,
        type: w.type,
        position: w.position,
        value: snap?.value ?? null,
        anomaly: snap?.anomalyFlag ?? false,
        anomalyExplanation: snap?.anomalyExplanation ?? null,
        ts: snap?.ts ?? null,
        history: numericHistory,
        investigationId: investigation?.id ?? null,
        investigationStatus: investigation?.status ?? null,
      };
    });

    const theme = getTheme(dash.themeId) ?? getTheme("default");

    return c.json({
      dashboardId,
      name: dash.name,
      themeId: dash.themeId,
      theme,
      widgets,
    });
  });

  app.get("/themes", (c) => c.json({ themes: listThemes() }));

  app.get("/themes/:id", (c) => {
    const theme = getTheme(c.req.param("id"));
    if (!theme) return c.json({ error: "not found" }, 404);
    return c.json({ theme });
  });

  // Write-side CRUD + AI routes used by the MCP thin client.
  app.route("/", buildRoutes());

  // Demo mock API — stand-ins for Stripe, Supabase, PostHog.
  // The demo flow tells Claude Desktop to point at /demo/* URLs as if
  // they were real external systems. Presenter spikes errors with
  // `curl -XPOST http://localhost:3737/demo/control/spike`.
  app.route("/demo", createMockApi());

  return app;
}

export async function startHttpServer(): Promise<void> {
  const app = buildHttpApp();
  serve({ fetch: app.fetch, port: PORT }, (info) => {
    log.info(`HTTP listening on http://localhost:${info.port}`);
  });
}
