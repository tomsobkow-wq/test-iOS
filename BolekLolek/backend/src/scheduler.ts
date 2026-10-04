import type { Db } from "./db.ts";
import type { FlightProvider } from "./flights.ts";
import type { Quota } from "./quota.ts";
import { checkDueWatches, type CheckSummary } from "./watches.ts";

/** Looks for due watches every `intervalMs`. Returns a function that stops it. */
export function startScheduler(
  deps: { db: Db; provider: FlightProvider; quota: Quota; now?: () => number; onTick?: (summary: CheckSummary) => void },
  intervalMs: number,
): () => void {
  let running = false;
  const timer = setInterval(async () => {
    if (running) return; // a slow search must not pile up ticks
    running = true;
    try {
      const summary = await checkDueWatches(deps.db, deps.provider, deps.quota, (deps.now ?? Date.now)());
      if (summary.checked || summary.alerts || summary.failed || summary.skippedNoQuota) deps.onTick?.(summary);
    } finally { running = false; }
  }, intervalMs);
  timer.unref();
  return () => clearInterval(timer);
}
