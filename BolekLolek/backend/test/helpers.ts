import type { Config } from "../src/config.ts";
import { openDb } from "../src/db.ts";
import type { FlightProvider, FlightQuery, FlightResult } from "../src/flights.ts";
import { Quota } from "../src/quota.ts";

export const config: Config = {
  port: 0, host: "127.0.0.1", apiToken: "test-token-0123456789", serpApiKey: "x", dbPath: ":memory:",
  monthlySearchLimit: 10, maxWatches: 2, defaultCheckEveryHours: 12, tickSeconds: 60,
};

/** A flight provider that answers with whatever price the test sets, and records every query. */
export class FakeFlights implements FlightProvider {
  priceMinor: number | null = 90_000;
  queries: FlightQuery[] = [];
  fail = false;
  async search(query: FlightQuery): Promise<FlightResult> {
    this.queries.push(query);
    if (this.fail) throw new Error("boom");
    if (this.priceMinor === null) return { offers: [] };
    return { offers: [{ priceMinor: this.priceMinor, currency: query.currency, airlines: ["TAP Air Portugal"], stops: 0, durationMinutes: 245,
      departs: { airport: query.origin, time: `${query.departDate} 06:15` }, arrives: { airport: query.destination, time: `${query.departDate} 10:20` }, flightNumbers: ["TP 1235"] }] };
  }
}

export function setup(limit = 10) {
  const db = openDb(":memory:");
  const quota = new Quota(db, limit);
  const provider = new FakeFlights();
  return { db, quota, provider, config: { ...config, monthlySearchLimit: limit } };
}

export const NOW = Date.parse("2026-10-05T09:00:00Z");
