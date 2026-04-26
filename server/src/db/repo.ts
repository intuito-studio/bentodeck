import { randomUUID } from "node:crypto";
import { getDb } from "./schema.js";
import type { Theme } from "../themes/presets.js";
import { PRESET_THEMES } from "../themes/presets.js";
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
     (id, name, type, url, method, headers_json, auth_header_key, auth_header_value, poll_interval_sec, needs_key)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
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
    input.needsKey ? 1 : 0,
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
  needs_key: number;
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
    needsKey: r.needs_key === 1,
    createdAt: r.created_at,
  };
}

/// Substitute the user's API key into the auth header value template that's
/// been waiting in the data_sources row, and clear the needs_key flag.
/// The auth_header_value column at this point still contains the literal
/// "{{API_KEY}}" placeholder the discoverer emitted; we replace it in place.
/// Returns the updated DataSource, or null if the source doesn't exist.
export function setDataSourceKey(
  id: string,
  apiKey: string,
): DataSource | null {
  const existing = getDataSource(id);
  if (!existing) return null;
  const template = existing.authHeaderValue ?? "";
  const substituted = template.includes("{{API_KEY}}")
    ? template.replace("{{API_KEY}}", apiKey)
    : // No placeholder in the template — fall back to a plain Bearer header
      // so simple "this API just wants Authorization: Bearer <key>" cases
      // still work even if the discoverer didn't emit a template.
      `Bearer ${apiKey}`;
  getDb()
    .prepare(
      `UPDATE data_sources
       SET auth_header_value = ?, needs_key = 0
       WHERE id = ?`,
    )
    .run(substituted, id);
  return getDataSource(id);
}

/// Put a data source back into the "needs key" state with the given header
/// value template. Used when a key the user supplied fails verification —
/// we want them to be able to retry without re-running discovery.
export function restoreNeedsKey(
  id: string,
  template: string,
): DataSource | null {
  if (!getDataSource(id)) return null;
  getDb()
    .prepare(
      `UPDATE data_sources
       SET auth_header_value = ?, needs_key = 1
       WHERE id = ?`,
    )
    .run(template, id);
  return getDataSource(id);
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
  // SQLite datetime('now') has 1s resolution; multiple snapshots written
  // in the same second otherwise have undefined order. AUTOINCREMENT id
  // is the strict tiebreaker that makes "latest" deterministic.
  const row = getDb()
    .prepare(
      `SELECT value_json, anomaly_flag, anomaly_explanation, ts
       FROM snapshots WHERE widget_id = ?
       ORDER BY ts DESC, id DESC LIMIT 1`,
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

export function latestSnapshotId(widgetId: string): number | null {
  const row = getDb()
    .prepare(
      `SELECT id FROM snapshots WHERE widget_id = ?
       ORDER BY ts DESC, id DESC LIMIT 1`,
    )
    .get(widgetId) as { id: number } | undefined;
  return row?.id ?? null;
}

export function recentSnapshots(widgetId: string, limit = 50): Array<{
  value: unknown;
  anomalyFlag: boolean;
  ts: string;
}> {
  const rows = getDb()
    .prepare(
      `SELECT value_json, anomaly_flag, ts FROM snapshots
       WHERE widget_id = ? ORDER BY ts DESC, id DESC LIMIT ?`,
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

// ---------- Themes ----------

export function seedPresetThemes(): void {
  const db = getDb();
  const stmt = db.prepare(
    `INSERT OR REPLACE INTO themes (id, name, is_preset, json)
     VALUES (?, ?, 1, ?)`,
  );
  for (const preset of PRESET_THEMES) {
    stmt.run(preset.id, preset.name, JSON.stringify(preset));
  }
}

export function saveTheme(theme: Theme, isPreset = false): Theme {
  getDb()
    .prepare(
      `INSERT OR REPLACE INTO themes (id, name, is_preset, json) VALUES (?, ?, ?, ?)`,
    )
    .run(theme.id, theme.name, isPreset ? 1 : 0, JSON.stringify(theme));
  return theme;
}

export function getTheme(id: string): Theme | null {
  const row = getDb()
    .prepare(`SELECT json FROM themes WHERE id = ?`)
    .get(id) as { json: string } | undefined;
  if (!row) return null;
  return JSON.parse(row.json) as Theme;
}

export function listThemes(): Theme[] {
  const rows = getDb()
    .prepare(
      `SELECT json FROM themes ORDER BY is_preset DESC, created_at DESC`,
    )
    .all() as Array<{ json: string }>;
  return rows.map((r) => JSON.parse(r.json) as Theme);
}

// ---------- KV (small backend-process settings) ----------

export function kvGet(key: string): string | null {
  const row = getDb()
    .prepare(`SELECT value FROM kv WHERE key = ?`)
    .get(key) as { value: string } | undefined;
  return row?.value ?? null;
}

export function kvSet(key: string, value: string): void {
  getDb()
    .prepare(
      `INSERT INTO kv (key, value) VALUES (?, ?)
       ON CONFLICT(key) DO UPDATE SET value = excluded.value`,
    )
    .run(key, value);
}

// ---------- Investigations ----------

export type Investigation = {
  id: string;
  widgetId: string;
  snapshotId: number | null;
  sessionId: string | null;
  status: "pending" | "running" | "done" | "failed";
  title: string | null;
  report: string | null;
  error: string | null;
  createdAt: string;
  completedAt: string | null;
};

type InvestigationRow = {
  id: string;
  widget_id: string;
  snapshot_id: number | null;
  session_id: string | null;
  status: Investigation["status"];
  title: string | null;
  report: string | null;
  error: string | null;
  created_at: string;
  completed_at: string | null;
};

function rowToInvestigation(r: InvestigationRow): Investigation {
  return {
    id: r.id,
    widgetId: r.widget_id,
    snapshotId: r.snapshot_id,
    sessionId: r.session_id,
    status: r.status,
    title: r.title,
    report: r.report,
    error: r.error,
    createdAt: r.created_at,
    completedAt: r.completed_at,
  };
}

export function createInvestigation(args: {
  id: string;
  widgetId: string;
  snapshotId?: number | null;
}): Investigation {
  getDb()
    .prepare(
      `INSERT INTO investigations (id, widget_id, snapshot_id, status)
       VALUES (?, ?, ?, 'pending')`,
    )
    .run(args.id, args.widgetId, args.snapshotId ?? null);
  return getInvestigation(args.id)!;
}

export function getInvestigation(id: string): Investigation | null {
  const row = getDb()
    .prepare(`SELECT * FROM investigations WHERE id = ?`)
    .get(id) as InvestigationRow | undefined;
  return row ? rowToInvestigation(row) : null;
}

export function listInvestigationsForWidget(
  widgetId: string,
  limit = 10,
): Investigation[] {
  const rows = getDb()
    .prepare(
      `SELECT * FROM investigations WHERE widget_id = ?
       ORDER BY created_at DESC LIMIT ?`,
    )
    .all(widgetId, limit) as InvestigationRow[];
  return rows.map(rowToInvestigation);
}

export function updateInvestigation(
  id: string,
  patch: Partial<
    Pick<Investigation, "status" | "sessionId" | "title" | "report" | "error">
  >,
): void {
  const set: string[] = [];
  const vals: unknown[] = [];
  if (patch.status !== undefined) {
    set.push("status = ?");
    vals.push(patch.status);
  }
  if (patch.sessionId !== undefined) {
    set.push("session_id = ?");
    vals.push(patch.sessionId);
  }
  if (patch.title !== undefined) {
    set.push("title = ?");
    vals.push(patch.title);
  }
  if (patch.report !== undefined) {
    set.push("report = ?");
    vals.push(patch.report);
  }
  if (patch.error !== undefined) {
    set.push("error = ?");
    vals.push(patch.error);
  }
  if (patch.status === "done" || patch.status === "failed") {
    set.push("completed_at = datetime('now')");
  }
  if (set.length === 0) return;
  vals.push(id);
  getDb()
    .prepare(`UPDATE investigations SET ${set.join(", ")} WHERE id = ?`)
    .run(...vals);
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
         ORDER BY ts DESC, id DESC LIMIT 1
       )`,
    )
    .run(flag ? 1 : 0, explanation, widgetId);
  return res.changes > 0;
}
