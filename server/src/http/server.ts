import { serve } from "@hono/node-server";
import { Hono } from "hono";
import {
  getDashboard,
  latestSnapshot,
  listDashboards,
  listWidgetsForDashboard,
} from "../db/repo.js";
import { log } from "../logger.js";

const PORT = Number(process.env.BENTODECK_HTTP_PORT ?? 3737);

export async function startHttpServer(): Promise<void> {
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
      return {
        id: w.id,
        title: w.title,
        type: w.type,
        position: w.position,
        value: snap?.value ?? null,
        anomaly: snap?.anomalyFlag ?? false,
        anomalyExplanation: snap?.anomalyExplanation ?? null,
        ts: snap?.ts ?? null,
      };
    });

    return c.json({
      dashboardId,
      name: dash.name,
      themeId: dash.themeId,
      widgets,
    });
  });

  serve({ fetch: app.fetch, port: PORT }, (info) => {
    log.info(`HTTP listening on http://localhost:${info.port}`);
  });
}
