import type { Db } from "./db.ts";

/** Counts searches per calendar month (UTC) and refuses to go past the limit, so the free plan is never overrun. */
export class Quota {
  private db: Db;
  readonly limit: number;

  constructor(db: Db, limit: number) {
    this.db = db;
    this.limit = limit;
  }

  static month(nowMs: number): string {
    return new Date(nowMs).toISOString().slice(0, 7);
  }

  used(nowMs: number): number {
    const row = this.db.prepare("SELECT searches FROM usage WHERE month = ?").get(Quota.month(nowMs)) as { searches: number } | undefined;
    return row?.searches ?? 0;
  }

  remaining(nowMs: number): number {
    return Math.max(0, this.limit - this.used(nowMs));
  }

  /** Takes one search. Returns false, taking nothing, when the month is used up. */
  consume(nowMs: number): boolean {
    if (this.remaining(nowMs) <= 0) return false;
    this.db.prepare("INSERT INTO usage (month, searches) VALUES (?, 1) ON CONFLICT(month) DO UPDATE SET searches = searches + 1").run(Quota.month(nowMs));
    return true;
  }
}
