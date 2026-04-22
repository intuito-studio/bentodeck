import Database from "better-sqlite3";
import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { log } from "../logger.js";

const DATA_DIR = process.env.BENTODECK_DATA_DIR ?? "./data";
const DB_PATH = join(DATA_DIR, "bentodeck.sqlite");

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
`;

export function initDb(): Database.Database {
  if (dbInstance) return dbInstance;
  mkdirSync(DATA_DIR, { recursive: true });
  const db = new Database(DB_PATH);
  db.pragma("journal_mode = WAL");
  db.pragma("foreign_keys = ON");
  db.exec(SCHEMA);
  dbInstance = db;
  log.info(`SQLite initialized at ${DB_PATH}`);
  return db;
}

export function getDb(): Database.Database {
  if (!dbInstance) throw new Error("DB not initialized; call initDb() first");
  return dbInstance;
}
