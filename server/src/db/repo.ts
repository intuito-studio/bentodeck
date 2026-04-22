import { randomUUID } from "node:crypto";
import { getDb } from "./schema.js";
import type {
  Dashboard,
  DashboardInput,
  DataSource,
  DataSourceInput,
  Widget,
  WidgetInput,
} from "../types/schemas.js";

// ---------- Dashboards ----------

export function createDashboard(input: DashboardInput): Dashboard {
  const id = randomUUID();
  const db = getDb();
  db.prepare(
    `INSERT INTO dashboards (id, name, theme_id) VALUES (?, ?, ?)`,
  ).run(id, input.name, input.themeId);
  return getDashboard(id)!;
}

export function getDashboard(id: string): Dashboard | null {
  const row = getDb()
    .prepare(
      `SELECT id, name, theme_id AS themeId, created_at AS createdAt
       FROM dashboards WHERE id = ?`,
    )
    .get(id) as Dashboard | undefined;
  return row ?? null;
}

export function listDashboards(): Dashboard[] {
  return getDb()
    .prepare(
      `SELECT id, name, theme_id AS themeId, created_at AS createdAt
       FROM dashboards ORDER BY created_at DESC`,
    )
    .all() as Dashboard[];
}

export function deleteDashboard(id: string): boolean {
  const res = getDb().prepare(`DELETE FROM dashboards WHERE id = ?`).run(id);
  return res.changes > 0;
}

export function setDashboardTheme(id: string, themeId: string): boolean {
  const res = getDb()
    .prepare(`UPDATE dashboards SET theme_id = ? WHERE id = ?`)
    .run(themeId, id);
  return res.changes > 0;
}

// ---------- Data sources ----------

export function createDataSource(input: DataSourceInput): DataSource {
  const id = randomUUID();
  const db = getDb();
  db.prepare(
    `INSERT INTO data_sources
     (id, name, type, url, method, headers_json, auth_header_key, auth_header_value, poll_interval_sec)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  ).run(
    id,
    input.name,
    input.type,
    input.url,
    input.method,
    input.headers ? JSON.stringify(input.headers) : null,
    input.authHeaderKey ?? null,
    input.authHeaderValue ?? null,
    input.pollIntervalSec,
  );
  return getDataSource(id)!;
}

type DataSourceRow = {
  id: string;
  name: string;
  type: "rest";
  url: string;
  method: "GET" | "POST";
  headers_json: string | null;
  auth_header_key: string | null;
  auth_header_value: string | null;
  poll_interval_sec: number;
  last_sample_json: string | null;
  created_at: string;
};

function rowToDataSource(r: DataSourceRow): DataSource {
  return {
    id: r.id,
    name: r.name,
    type: r.type,
    url: r.url,
    method: r.method,
    headers: r.headers_json ? JSON.parse(r.headers_json) : undefined,
    authHeaderKey: r.auth_header_key ?? undefined,
    authHeaderValue: r.auth_header_value ?? undefined,
    pollIntervalSec: r.poll_interval_sec,
    lastSampleJson: r.last_sample_json,
    createdAt: r.created_at,
  };
}

export function getDataSource(id: string): DataSource | null {
  const row = getDb()
    .prepare(`SELECT * FROM data_sources WHERE id = ?`)
    .get(id) as DataSourceRow | undefined;
  return row ? rowToDataSource(row) : null;
}

export function listDataSources(): DataSource[] {
  const rows = getDb()
    .prepare(`SELECT * FROM data_sources ORDER BY created_at DESC`)
    .all() as DataSourceRow[];
  return rows.map(rowToDataSource);
}

export function saveLastSample(id: string, sampleJson: string): void {
  getDb()
    .prepare(`UPDATE data_sources SET last_sample_json = ? WHERE id = ?`)
    .run(sampleJson, id);
}

// ---------- Widgets ----------

export function createWidget(input: WidgetInput): Widget {
  const id = randomUUID();
  getDb()
    .prepare(
      `INSERT INTO widgets (id, dashboard_id, source_id, type, title, transform_expr, position)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
    )
    .run(
      id,
      input.dashboardId,
      input.sourceId,
      input.type,
      input.title,
      input.transformExpr,
      input.position,
    );
  return getWidget(id)!;
}

type WidgetRow = {
  id: string;
  dashboard_id: string;
  source_id: string;
  type: Widget["type"];
  title: string;
  transform_expr: string;
  position: number;
  created_at: string;
};

function rowToWidget(r: WidgetRow): Widget {
  return {
    id: r.id,
    dashboardId: r.dashboard_id,
    sourceId: r.source_id,
    type: r.type,
    title: r.title,
    transformExpr: r.transform_expr,
    position: r.position,
    createdAt: r.created_at,
  };
}

export function getWidget(id: string): Widget | null {
  const row = getDb()
    .prepare(`SELECT * FROM widgets WHERE id = ?`)
    .get(id) as WidgetRow | undefined;
  return row ? rowToWidget(row) : null;
}

export function listWidgetsForDashboard(dashboardId: string): Widget[] {
  const rows = getDb()
    .prepare(
      `SELECT * FROM widgets WHERE dashboard_id = ?
       ORDER BY position ASC, created_at ASC`,
    )
    .all(dashboardId) as WidgetRow[];
  return rows.map(rowToWidget);
}

export function listAllWidgets(): Widget[] {
  const rows = getDb()
    .prepare(`SELECT * FROM widgets ORDER BY created_at DESC`)
    .all() as WidgetRow[];
  return rows.map(rowToWidget);
}

// ---------- Snapshots ----------

export function writeSnapshot(args: {
  widgetId: string;
  value: unknown;
  anomalyFlag?: boolean;
  anomalyExplanation?: string | null;
}): void {
  getDb()
    .prepare(
      `INSERT INTO snapshots (widget_id, value_json, anomaly_flag, anomaly_explanation)
       VALUES (?, ?, ?, ?)`,
    )
    .run(
      args.widgetId,
      JSON.stringify(args.value),
      args.anomalyFlag ? 1 : 0,
      args.anomalyExplanation ?? null,
    );
}

export function latestSnapshot(widgetId: string): {
  value: unknown;
  anomalyFlag: boolean;
  anomalyExplanation: string | null;
  ts: string;
} | null {
  const row = getDb()
    .prepare(
      `SELECT value_json, anomaly_flag, anomaly_explanation, ts
       FROM snapshots WHERE widget_id = ?
       ORDER BY ts DESC LIMIT 1`,
    )
    .get(widgetId) as
    | {
        value_json: string;
        anomaly_flag: number;
        anomaly_explanation: string | null;
        ts: string;
      }
    | undefined;
  if (!row) return null;
  return {
    value: JSON.parse(row.value_json),
    anomalyFlag: row.anomaly_flag === 1,
    anomalyExplanation: row.anomaly_explanation,
    ts: row.ts,
  };
}

export function recentSnapshots(widgetId: string, limit = 50): Array<{
  value: unknown;
  anomalyFlag: boolean;
  ts: string;
}> {
  const rows = getDb()
    .prepare(
      `SELECT value_json, anomaly_flag, ts FROM snapshots
       WHERE widget_id = ? ORDER BY ts DESC LIMIT ?`,
    )
    .all(widgetId, limit) as Array<{
    value_json: string;
    anomaly_flag: number;
    ts: string;
  }>;
  return rows.map((r) => ({
    value: JSON.parse(r.value_json),
    anomalyFlag: r.anomaly_flag === 1,
    ts: r.ts,
  }));
}

export function markLatestSnapshotAnomaly(
  widgetId: string,
  flag: boolean,
  explanation: string | null,
): boolean {
  const res = getDb()
    .prepare(
      `UPDATE snapshots
       SET anomaly_flag = ?, anomaly_explanation = ?
       WHERE id = (
         SELECT id FROM snapshots WHERE widget_id = ?
         ORDER BY ts DESC LIMIT 1
       )`,
    )
    .run(flag ? 1 : 0, explanation, widgetId);
  return res.changes > 0;
}
