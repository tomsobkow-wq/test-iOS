import { DatabaseSync } from "node:sqlite";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";

export type Db = DatabaseSync;

export function openDb(path: string): Db {
  if (path !== ":memory:") mkdirSync(dirname(path), { recursive: true });
  const db = new DatabaseSync(path);
  db.exec(`
    PRAGMA journal_mode = WAL;
    CREATE TABLE IF NOT EXISTS watches (
      id TEXT PRIMARY KEY,
      user TEXT NOT NULL,
      origin TEXT NOT NULL,
      destination TEXT NOT NULL,
      depart_date TEXT NOT NULL,
      return_date TEXT,
      adults INTEGER NOT NULL DEFAULT 1,
      currency TEXT NOT NULL,
      threshold_minor INTEGER NOT NULL,
      every_hours INTEGER NOT NULL,
      next_run_at INTEGER NOT NULL,
      last_price_minor INTEGER,
      last_checked_at INTEGER,
      last_alert_price_minor INTEGER,
      active INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS topic_watches (
      id TEXT PRIMARY KEY,
      user TEXT NOT NULL,
      kind TEXT NOT NULL,
      query TEXT NOT NULL,
      country TEXT NOT NULL,
      language TEXT NOT NULL,
      currency TEXT,
      threshold_minor INTEGER,
      every_hours INTEGER NOT NULL,
      next_run_at INTEGER NOT NULL,
      last_price_minor INTEGER,
      last_checked_at INTEGER,
      last_alert_price_minor INTEGER,
      seen_json TEXT NOT NULL DEFAULT '[]',
      active INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS alerts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user TEXT NOT NULL,
      watch_id TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      title TEXT NOT NULL,
      body TEXT NOT NULL,
      price_minor INTEGER NOT NULL,
      currency TEXT NOT NULL,
      seen INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE IF NOT EXISTS usage (month TEXT PRIMARY KEY, searches INTEGER NOT NULL);
  `);
  return db;
}
