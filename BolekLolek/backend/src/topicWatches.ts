// Watches that are not about one flight: the price of a product, or new headlines on a topic.
import { randomUUID } from "node:crypto";
import type { Db } from "./db.ts";
import type { NewsProvider } from "./news.ts";
import { sourceLink, type SourceLink } from "./links.ts";
import { overlap, words } from "./text.ts";
import type { WebProvider } from "./web.ts";
import type { ProductProvider } from "./shopping.ts";
import { relevantOffers } from "./shopping.ts";
import { money } from "./flights.ts";
import type { Quota } from "./quota.ts";

const HOUR = 3_600_000;

export interface TopicWatch {
  id: string;
  kind: "product" | "news" | "web";
  query: string;
  location: string | null;
  country: string;
  language: string;
  currency: string | null;
  thresholdMinor: number | null;
  everyHours: number;
  nextRunAt: number;
  lastPriceMinor: number | null;
  lastCheckedAt: number | null;
  seen: string[];
}

type Row = Record<string, unknown>;
const toWatch = (r: Row): TopicWatch => ({
  id: r.id as string, kind: r.kind as "product" | "news" | "web", query: r.query as string, location: (r.location as string | null) ?? null, country: r.country as string, language: r.language as string,
  currency: (r.currency as string | null) ?? null, thresholdMinor: (r.threshold_minor as number | null) ?? null, everyHours: r.every_hours as number,
  nextRunAt: r.next_run_at as number, lastPriceMinor: (r.last_price_minor as number | null) ?? null, lastCheckedAt: (r.last_checked_at as number | null) ?? null,
  seen: JSON.parse((r.seen_json as string) || "[]") as string[],
});

export interface NewTopicWatch {
  kind: "product" | "news" | "web";
  query: string;
  location?: string;
  country: string;
  language: string;
  currency?: string;
  thresholdMinor?: number;
  everyHours: number;
}

/** Active watches of every kind count against one limit, so the monthly search allowance cannot be eaten by a pile of them. */
export function countActiveWatches(db: Db, user: string): number {
  const flights = (db.prepare("SELECT COUNT(*) AS n FROM watches WHERE user = ? AND active = 1").get(user) as { n: number }).n;
  const topics = (db.prepare("SELECT COUNT(*) AS n FROM topic_watches WHERE user = ? AND active = 1").get(user) as { n: number }).n;
  return flights + topics;
}

export function createTopicWatch(db: Db, user: string, input: NewTopicWatch, nowMs: number, maxWatches: number): TopicWatch {
  const active = countActiveWatches(db, user);
  if (active >= maxWatches) throw new Error(`You already have ${active} active watches, which is the limit (${maxWatches}). Stop one first.`);
  const id = randomUUID().slice(0, 8);
  db.prepare(`INSERT INTO topic_watches (id, user, kind, query, location, country, language, currency, threshold_minor, every_hours, next_run_at, created_at)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
    .run(id, user, input.kind, input.query, input.location ?? null, input.country, input.language, input.currency ?? null, input.thresholdMinor ?? null, input.everyHours, nowMs, nowMs);
  return toWatch(db.prepare("SELECT * FROM topic_watches WHERE id = ?").get(id) as Row);
}

export function listTopicWatches(db: Db, user: string): TopicWatch[] {
  return (db.prepare("SELECT * FROM topic_watches WHERE user = ? AND active = 1 ORDER BY created_at").all(user) as Row[]).map(toWatch);
}

export function stopTopicWatch(db: Db, user: string, id: string): boolean {
  return Number(db.prepare("UPDATE topic_watches SET active = 0 WHERE user = ? AND id = ? AND active = 1").run(user, id).changes) > 0;
}

export function describeTopicWatch(w: TopicWatch): string {
  if (w.kind === "web") return `[${w.id}] new web results for "${w.query}"${w.location ? ` near ${w.location}` : ""}: alert when new relevant results appear, checked every ${w.everyHours}h`;
  if (w.kind === "news") return `[${w.id}] news on "${w.query}" (${w.language}, ${w.country}): alert on new headlines, checked every ${w.everyHours}h`;
  const last = w.lastPriceMinor === null ? "not checked yet" : `lowest seen ${money(w.lastPriceMinor, w.currency ?? "")}`;
  return `[${w.id}] product "${w.query}": alert at or below ${money(w.thresholdMinor ?? 0, w.currency ?? "")}, checked every ${w.everyHours}h, ${last}`;
}

export interface TopicCheckSummary { checked: number; alerts: number; skippedNoQuota: number; failed: number }

function addAlert(db: Db, watchId: string, nowMs: number, title: string, body: string, priceMinor: number, currency: string, links: SourceLink[] = []): void {
  db.prepare("INSERT INTO alerts (user, watch_id, created_at, title, body, price_minor, currency, links_json) SELECT user, id, ?, ?, ?, ?, ?, ? FROM topic_watches WHERE id = ?")
    .run(nowMs, title, body, priceMinor, currency, links.length ? JSON.stringify(links.slice(0, 5)) : null, watchId);
}

/**
 * Checks every due product or news watch. A product alerts once per price (a price at least 1% lower alerts again);
 * a news watch alerts on headlines it has not shown before. The first news check only learns what is already out there,
 * so a new watch does not start with a flood.
 */
export async function checkDueTopicWatches(
  db: Db, providers: { shopping?: ProductProvider; news?: NewsProvider; web?: WebProvider }, quota: Quota, nowMs: number,
): Promise<TopicCheckSummary> {
  const summary: TopicCheckSummary = { checked: 0, alerts: 0, skippedNoQuota: 0, failed: 0 };
  const due = (db.prepare("SELECT * FROM topic_watches WHERE active = 1 AND next_run_at <= ? ORDER BY next_run_at").all(nowMs) as Row[]).map(toWatch);

  for (const watch of due) {
    const provider = watch.kind === "product" ? providers.shopping : watch.kind === "news" ? providers.news : providers.web;
    if (!provider) continue;
    if (!quota.consume(nowMs)) { summary.skippedNoQuota += 1; continue; }
    try {
      if (watch.kind === "product") {
        const offers = relevantOffers(watch.query, await providers.shopping!.search({ query: watch.query, country: watch.country, language: watch.language }));
        summary.checked += 1;
        const cheapest = [...offers].sort((a, b) => a.priceMinor - b.priceMinor)[0];
        db.prepare("UPDATE topic_watches SET last_checked_at = ?, last_price_minor = ?, next_run_at = ? WHERE id = ?")
          .run(nowMs, cheapest?.priceMinor ?? null, nowMs + watch.everyHours * HOUR, watch.id);
        if (!cheapest || watch.thresholdMinor === null || cheapest.priceMinor > watch.thresholdMinor) continue;
        const lastAlert = (db.prepare("SELECT last_alert_price_minor AS p FROM topic_watches WHERE id = ?").get(watch.id) as { p: number | null }).p;
        if (lastAlert !== null && cheapest.priceMinor >= lastAlert * 0.99) continue;
        addAlert(db, watch.id, nowMs, `Price drop: ${watch.query}`,
          `${money(cheapest.priceMinor, cheapest.currency)} at ${cheapest.shop} (your limit ${money(watch.thresholdMinor, cheapest.currency)}): ${cheapest.title.slice(0, 80)}`, cheapest.priceMinor, cheapest.currency);
        db.prepare("UPDATE topic_watches SET last_alert_price_minor = ? WHERE id = ?").run(cheapest.priceMinor, watch.id);
        summary.alerts += 1;
      } else if (watch.kind === "web") {
        const results = await providers.web!.search({ query: watch.query, country: watch.country, language: watch.language, location: watch.location ?? undefined });
        summary.checked += 1;
        // Only results that are really about the thing count: most of the query's words must be in the title or snippet.
        const wanted = words(watch.query);
        const relevant = results.filter((r) => overlap(wanted, `${r.title} ${r.snippet}`) >= 0.6);
        const known = new Set(watch.seen);
        const fresh = relevant.filter((r) => !known.has(r.link));
        const seen = [...fresh.map((r) => r.link), ...watch.seen].slice(0, 300);
        db.prepare("UPDATE topic_watches SET last_checked_at = ?, next_run_at = ?, seen_json = ? WHERE id = ?")
          .run(nowMs, nowMs + watch.everyHours * HOUR, JSON.stringify(seen), watch.id);
        if (watch.lastCheckedAt === null || fresh.length === 0) continue;   // the first check only learns what is already there
        const lines = fresh.slice(0, 3).map((r) => `${r.source}: ${r.title}${r.snippet ? ` | ${r.snippet.slice(0, 100)}` : ""}`).join(" || ");
        const links = fresh.map((r) => sourceLink(r.title, r.source, r.link)).filter((l): l is SourceLink => !!l);
        addAlert(db, watch.id, nowMs, `New results: ${watch.query}`, `${fresh.length} new ${fresh.length === 1 ? "result" : "results"}. ${lines}`, 0, "", links);
        summary.alerts += 1;
      } else {
        const items = await providers.news!.search({ query: watch.query, country: watch.country, language: watch.language });
        summary.checked += 1;
        const known = new Set(watch.seen);
        const fresh = items.filter((item) => !known.has(item.link));
        const seen = [...fresh.map((i) => i.link), ...watch.seen].slice(0, 200);
        db.prepare("UPDATE topic_watches SET last_checked_at = ?, next_run_at = ?, seen_json = ? WHERE id = ?")
          .run(nowMs, nowMs + watch.everyHours * HOUR, JSON.stringify(seen), watch.id);
        const firstCheck = watch.lastCheckedAt === null;
        if (firstCheck || fresh.length === 0) continue;
        const top = fresh.slice(0, 3).map((item) => `${item.source}: ${item.title}`).join(" | ");
        addAlert(db, watch.id, nowMs, `News: ${watch.query}`, `${fresh.length} new ${fresh.length === 1 ? "headline" : "headlines"}. ${top}`, 0, "");
        summary.alerts += 1;
      }
    } catch {
      summary.failed += 1;
      db.prepare("UPDATE topic_watches SET next_run_at = ? WHERE id = ?").run(nowMs + HOUR, watch.id);
    }
  }
  return summary;
}
