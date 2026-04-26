import Database from "better-sqlite3";
import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { log } from "../logger.js";

let dbInstance: Database.Database | null = null;

const SCHEMA = `
  CREATE TABLE IF NOT EXISTS dashboards (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    theme_id    TEXT NOT NULL DEFAULT 'default',
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
  );

  CREATE TABLE IF NOT EXISTS data_sources (
    id                 TEXT PRIMARY KEY,
    name               TEXT NOT NULL,
    type               TEXT NOT NULL,
    url                TEXT NOT NULL,
    method             TEXT NOT NULL DEFAULT 'GET',
    headers_json       TEXT,
    auth_header_key    TEXT,
    auth_header_value  TEXT,
    poll_interval_sec  INTEGER NOT NULL DEFAULT 60,
    last_sample_json   TEXT,
    created_at         TEXT NOT NULL DEFAULT (datetime('now'))
  );

  CREATE TABLE IF NOT EXISTS widgets (
    id             TEXT PRIMARY KEY,
    dashboard_id   TEXT NOT NULL,
    source_id      TEXT NOT NULL,
    type           TEXT NOT NULL,
    title          TEXT NOT NULL,
    transform_expr TEXT NOT NULL,
    position       INTEGER NOT NULL DEFAULT 0,
    created_at     TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (dashboard_id) REFERENCES dashboards(id) ON DELETE CASCADE,
    FOREIGN KEY (source_id)    REFERENCES data_sources(id) ON DELETE CASCADE
  );

  CREATE TABLE IF NOT EXISTS snapshots (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    widget_id           TEXT NOT NULL,
    value_json          TEXT NOT NULL,
    anomaly_flag        INTEGER NOT NULL DEFAULT 0,
    anomaly_explanation TEXT,
    ts                  TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (widget_id) REFERENCES widgets(id) ON DELETE CASCADE
  );

  CREATE INDEX IF NOT EXISTS idx_snapshots_widget_ts
    ON snapshots(widget_id, ts DESC);

  CREATE TABLE IF NOT EXISTS themes (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    is_preset   INTEGER NOT NULL DEFAULT 0,
    json        TEXT NOT NULL,
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
  );

  -- Long-running incident reports written by Claude Managed Agents.
  -- Decoupled from the per-snapshot quick anomaly explanation so a
  -- multi-paragraph investigation can take its time without blocking
  -- the wrist-buzz path.
  CREATE TABLE IF NOT EXISTS investigations (
    id            TEXT PRIMARY KEY,
    widget_id     TEXT NOT NULL,
    snapshot_id   INTEGER,
    session_id    TEXT,
    status        TEXT NOT NULL DEFAULT 'pending', -- pending | running | done | failed
    title         TEXT,
    report        TEXT,
    error         TEXT,
    created_at    TEXT NOT NULL DEFAULT (datetime('now')),
    completed_at  TEXT,
    FOREIGN KEY (widget_id) REFERENCES widgets(id) ON DELETE CASCADE
  );

  CREATE INDEX IF NOT EXISTS idx_investigations_widget_created
    ON investigations(widget_id, created_at DESC);

  -- Tiny KV table for backend-process settings that must outlive a restart
  -- (e.g., the cached Managed Agents agent_id and environment_id so we
  -- don't re-create them on every boot).
  CREATE TABLE IF NOT EXISTS kv (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
  );
`;

export function initDb(): Database.Database {
  if (dbInstance) return dbInstance;
  // Resolved at call time so tests/scripts can override BENTODECK_DATA_DIR
  // before initDb() runs.
  const dataDir = process.env.BENTODECK_DATA_DIR ?? "./data";
  const dbPath = join(dataDir, "bentodeck.sqlite");
  mkdirSync(dataDir, { recursive: true });
  const db = new Database(dbPath);
  db.pragma("journal_mode = WAL");
  db.pragma("foreign_keys = ON");
  db.exec(SCHEMA);
  dbInstance = db;
  log.info(`SQLite initialized at ${dbPath}`);
  return db;
}

export function getDb(): Database.Database {
  if (!dbInstance) throw new Error("DB not initialized; call initDb() first");
  return dbInstance;
}

// Test-only hook: close the current DB handle and null the singleton so a
// subsequent initDb() picks up a fresh BENTODECK_DATA_DIR. Do not call from
// production code.
export function __resetDbForTests(): void {
  if (dbInstance) {
    try {
      dbInstance.close();
    } catch {
      // ignore
    }
    dbInstance = null;
  }
}
