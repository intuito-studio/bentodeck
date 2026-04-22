import { serve } from "@hono/node-server";
import { Hono } from "hono";
import { getDb } from "../db/schema.js";
import { log } from "../logger.js";

const PORT = Number(process.env.BENTODECK_HTTP_PORT ?? 3737);

export async function startHttpServer(): Promise<void> {
  const app = new Hono();

  app.get("/health", (c) =>
    c.json({ ok: true, service: "bentodeck", version: "0.1.0" }),
  );

  // Dashboards list — used by the iOS app home screen.
  app.get("/dashboards", (c) => {
    const db = getDb();
    const rows = db
      .prepare(
        `SELECT id, name, theme_id, created_at FROM dashboards ORDER BY created_at DESC`,
      )
      .all();
    return c.json({ dashboards: rows });
  });

  // Snapshots for a given dashboard — what the iOS app + widget render.
  app.get("/dashboards/:id/snapshot", (c) => {
    const dashboardId = c.req.param("id");
    const db = getDb();
    const widgets = db
      .prepare(
        `SELECT id, title, type, position FROM widgets
         WHERE dashboard_id = ?
         ORDER BY position ASC, created_at ASC`,
      )
      .all(dashboardId) as Array<{
      id: string;
      title: string;
      type: string;
      position: number;
    }>;

    const latestStmt = db.prepare(
      `SELECT value_json, anomaly_flag, anomaly_explanation, ts
       FROM snapshots WHERE widget_id = ?
       ORDER BY ts DESC LIMIT 1`,
    );

    const widgetsWithData = widgets.map((w) => {
      const snap = latestStmt.get(w.id) as
        | {
            value_json: string;
            anomaly_flag: number;
            anomaly_explanation: string | null;
            ts: string;
          }
        | undefined;
      return {
        id: w.id,
        title: w.title,
        type: w.type,
        position: w.position,
        value: snap ? JSON.parse(snap.value_json) : null,
        anomaly: snap?.anomaly_flag === 1,
        anomalyExplanation: snap?.anomaly_explanation ?? null,
        ts: snap?.ts ?? null,
      };
    });

    return c.json({ dashboardId, widgets: widgetsWithData });
  });

  serve({ fetch: app.fetch, port: PORT }, (info) => {
    log.info(`HTTP listening on http://localhost:${info.port}`);
  });
}
