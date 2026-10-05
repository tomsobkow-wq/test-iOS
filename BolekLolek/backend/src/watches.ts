import { randomUUID } from "node:crypto";
import type { Db } from "./db.ts";
import type { FlightProvider, FlightQuery } from "./flights.ts";
import { money } from "./flights.ts";
import type { Quota } from "./quota.ts";

const HOUR = 3_600_000;

export interface Watch {
  id: string;
  origin: string;
  destination: string;
  departDate: string;
  returnDate: string | null;
  adults: number;
  currency: string;
  thresholdMinor: number;
  everyHours: number;
  nextRunAt: number;
  lastPriceMinor: number | null;
  lastCheckedAt: number | null;
  active: boolean;
}

export interface Alert {
  id: number;
  watchId: string;
  createdAt: number;
  title: string;
  body: string;
  priceMinor: number;
  currency: string;
  seen: boolean;
  links: Array<{ title: string; site: string; url: string }>;
}

type WatchRow = Record<string, unknown>;
const toWatch = (r: WatchRow): Watch => ({
  id: r.id as string, origin: r.origin as string, destination: r.destination as string, departDate: r.depart_date as string,
  returnDate: (r.return_date as string | null) ?? null, adults: r.adults as number, currency: r.currency as string,
  thresholdMinor: r.threshold_minor as number, everyHours: r.every_hours as number, nextRunAt: r.next_run_at as number,
  lastPriceMinor: (r.last_price_minor as number | null) ?? null, lastCheckedAt: (r.last_checked_at as number | null) ?? null, active: r.active === 1,
});

/** What a watch costs against the monthly search allowance. */
export const searchesPerMonth = (everyHours: number) => Math.ceil((30 * 24) / everyHours);

export interface NewWatch {
  origin: string; destination: string; departDate: string; returnDate?: string; adults: number; currency: string;
  thresholdMinor: number; everyHours: number;
}

export function createWatch(db: Db, user: string, input: NewWatch, nowMs: number, maxWatches: number): Watch {
  const active = (db.prepare("SELECT COUNT(*) AS n FROM watches WHERE user = ? AND active = 1").get(user) as { n: number }).n;
  if (active >= maxWatches) throw new Error(`You already have ${active} active price watches, which is the limit (${maxWatches}). Stop one first.`);
  const id = randomUUID().slice(0, 8);
  db.prepare(`INSERT INTO watches (id, user, origin, destination, depart_date, return_date, adults, currency, threshold_minor, every_hours, next_run_at, created_at)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
    .run(id, user, input.origin, input.destination, input.departDate, input.returnDate ?? null, input.adults, input.currency, input.thresholdMinor, input.everyHours, nowMs, nowMs);
  return toWatch(db.prepare("SELECT * FROM watches WHERE id = ?").get(id) as WatchRow);
}

export function listWatches(db: Db, user: string): Watch[] {
  return (db.prepare("SELECT * FROM watches WHERE user = ? AND active = 1 ORDER BY created_at").all(user) as WatchRow[]).map(toWatch);
}

export function stopWatch(db: Db, user: string, id: string): boolean {
  return Number(db.prepare("UPDATE watches SET active = 0 WHERE user = ? AND id = ? AND active = 1").run(user, id).changes) > 0;
}

export function describeWatch(w: Watch): string {
  const trip = `${w.origin} -> ${w.destination}, ${w.departDate}${w.returnDate ? ` (return ${w.returnDate})` : " (one way)"}`;
  const last = w.lastPriceMinor === null ? "not checked yet" : `last seen ${money(w.lastPriceMinor, w.currency)}`;
  return `[${w.id}] ${trip}: alert below ${money(w.thresholdMinor, w.currency)}, checked every ${w.everyHours}h, ${last}`;
}

export function listAlerts(db: Db, user: string, afterId: number): Alert[] {
  return (db.prepare("SELECT * FROM alerts WHERE user = ? AND id > ? ORDER BY id").all(user, afterId) as WatchRow[]).map((r) => ({
    id: r.id as number, watchId: r.watch_id as string, createdAt: r.created_at as number, title: r.title as string, body: r.body as string,
    priceMinor: r.price_minor as number, currency: r.currency as string, seen: r.seen === 1,
    links: r.links_json ? (JSON.parse(r.links_json as string) as Alert["links"]) : [],
  }));
}

export function markAlertsSeen(db: Db, user: string, upToId: number): void {
  db.prepare("UPDATE alerts SET seen = 1 WHERE user = ? AND id <= ?").run(user, upToId);
}

export interface CheckSummary { checked: number; alerts: number; skippedNoQuota: number; failed: number; expired: number }

/**
 * Looks at every watch that is due. A price at or below the threshold becomes an alert, but only once per price:
 * the same fare is not announced again, a fare at least 1% lower is.
 */
export async function checkDueWatches(db: Db, provider: FlightProvider, quota: Quota, nowMs: number): Promise<CheckSummary> {
  const summary: CheckSummary = { checked: 0, alerts: 0, skippedNoQuota: 0, failed: 0, expired: 0 };
  const due = (db.prepare("SELECT * FROM watches WHERE active = 1 AND next_run_at <= ? ORDER BY next_run_at").all(nowMs) as WatchRow[]).map(toWatch);
  const today = new Date(nowMs).toISOString().slice(0, 10);

  for (const watch of due) {
    if (watch.departDate < today) {
      db.prepare("UPDATE watches SET active = 0 WHERE id = ?").run(watch.id);
      summary.expired += 1;
      continue;
    }
    if (!quota.consume(nowMs)) { summary.skippedNoQuota += 1; continue; }

    const query: FlightQuery = { origin: watch.origin, destination: watch.destination, departDate: watch.departDate, returnDate: watch.returnDate ?? undefined, adults: watch.adults, currency: watch.currency };
    try {
      const result = await provider.search(query);
      summary.checked += 1;
      const cheapest = result.offers[0];
      db.prepare("UPDATE watches SET last_checked_at = ?, last_price_minor = ?, next_run_at = ? WHERE id = ?")
        .run(nowMs, cheapest?.priceMinor ?? null, nowMs + watch.everyHours * HOUR, watch.id);
      if (!cheapest || cheapest.priceMinor > watch.thresholdMinor) continue;

      const lastAlert = (db.prepare("SELECT last_alert_price_minor AS p FROM watches WHERE id = ?").get(watch.id) as { p: number | null }).p;
      if (lastAlert !== null && cheapest.priceMinor >= lastAlert * 0.99) continue;

      const trip = `${watch.origin} to ${watch.destination}, ${watch.departDate}`;
      db.prepare("INSERT INTO alerts (user, watch_id, created_at, title, body, price_minor, currency) SELECT user, id, ?, ?, ?, ?, ? FROM watches WHERE id = ?")
        .run(nowMs, `Price drop: ${trip}`, `${money(cheapest.priceMinor, watch.currency)} (your limit ${money(watch.thresholdMinor, watch.currency)}). ${cheapest.airlines.join(" + ")}, ${cheapest.stops === 0 ? "direct" : cheapest.stops + " stop"}.`,
             cheapest.priceMinor, watch.currency, watch.id);
      db.prepare("UPDATE watches SET last_alert_price_minor = ? WHERE id = ?").run(cheapest.priceMinor, watch.id);
      summary.alerts += 1;
    } catch {
      // Try again in an hour; do not give up on the watch because of one bad answer.
      summary.failed += 1;
      db.prepare("UPDATE watches SET next_run_at = ? WHERE id = ?").run(nowMs + HOUR, watch.id);
    }
  }
  return summary;
}
