import type { Db } from "./db.ts";
import type { FlightProvider } from "./flights.ts";
import type { NewsProvider } from "./news.ts";
import type { Quota } from "./quota.ts";
import type { ProductProvider } from "./shopping.ts";
import { checkDueTopicWatches } from "./topicWatches.ts";
import { checkDueWatches, type CheckSummary } from "./watches.ts";

/** Looks for due watches every `intervalMs`. Returns a function that stops it. */
export function startScheduler(
  deps: { db: Db; provider?: FlightProvider; shopping?: ProductProvider; news?: NewsProvider; quota: Quota; now?: () => number; onTick?: (summary: CheckSummary) => void },
  intervalMs: number,
): () => void {
  let running = false;
  const timer = setInterval(async () => {
    if (running) return; // a slow search must not pile up ticks
    running = true;
    try {
      const nowMs = (deps.now ?? Date.now)();
      const flights = deps.provider ? await checkDueWatches(deps.db, deps.provider, deps.quota, nowMs) : { checked: 0, alerts: 0, skippedNoQuota: 0, failed: 0, expired: 0 };
      const topics = await checkDueTopicWatches(deps.db, { shopping: deps.shopping, news: deps.news }, deps.quota, nowMs);
      const summary: CheckSummary = {
        checked: flights.checked + topics.checked, alerts: flights.alerts + topics.alerts, skippedNoQuota: flights.skippedNoQuota + topics.skippedNoQuota,
        failed: flights.failed + topics.failed, expired: flights.expired,
      };
      if (summary.checked || summary.alerts || summary.failed || summary.skippedNoQuota) deps.onTick?.(summary);
    } finally { running = false; }
  }, intervalMs);
  timer.unref();
  return () => clearInterval(timer);
}
