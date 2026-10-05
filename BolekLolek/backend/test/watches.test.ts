import { test } from "node:test";
import assert from "node:assert/strict";
import { checkDueWatches, createWatch, listAlerts, listWatches, searchesPerMonth, stopWatch } from "../src/watches.ts";
import { NOW, setup } from "./helpers.ts";

const HOUR = 3_600_000;
const trip = { origin: "WAW", destination: "LIS", departDate: "2026-11-14", adults: 1, currency: "PLN", thresholdMinor: 90_000, everyHours: 12 };

test("a price at or below the limit raises one alert, and the same price is not announced twice", async () => {
  const { db, quota, provider } = setup();
  createWatch(db, "default", trip, NOW, 3);
  provider.priceMinor = 84_200;

  assert.equal((await checkDueWatches(db, provider, quota, NOW)).alerts, 1);
  const [alert] = listAlerts(db, "default", 0);
  assert.match(alert.title, /Price drop: WAW to LIS, 2026-11-14/);
  assert.match(alert.body, /842\.00 PLN \(your limit 900\.00 PLN\)/);

  // Twelve hours later the price is the same: no new alert.
  assert.equal((await checkDueWatches(db, provider, quota, NOW + 12 * HOUR)).alerts, 0);
  // A little lower (under 1%): still quiet. Clearly lower: alert again.
  provider.priceMinor = 83_800;
  assert.equal((await checkDueWatches(db, provider, quota, NOW + 24 * HOUR)).alerts, 0);
  provider.priceMinor = 79_900;
  assert.equal((await checkDueWatches(db, provider, quota, NOW + 36 * HOUR)).alerts, 1);
  assert.equal(listAlerts(db, "default", 0).length, 2);
});

test("a price above the limit is recorded but raises nothing", async () => {
  const { db, quota, provider } = setup();
  const watch = createWatch(db, "default", trip, NOW, 3);
  provider.priceMinor = 120_000;
  const summary = await checkDueWatches(db, provider, quota, NOW);
  assert.deepEqual([summary.checked, summary.alerts], [1, 0]);
  assert.equal(listWatches(db, "default")[0].lastPriceMinor, 120_000);
  assert.equal(listWatches(db, "default")[0].nextRunAt, NOW + 12 * HOUR);
  assert.equal(watch.active, true);
});

test("watches are only checked when due", async () => {
  const { db, quota, provider } = setup();
  createWatch(db, "default", trip, NOW, 3);
  await checkDueWatches(db, provider, quota, NOW);
  await checkDueWatches(db, provider, quota, NOW + 5 * HOUR);
  assert.equal(provider.queries.length, 1);
  await checkDueWatches(db, provider, quota, NOW + 12 * HOUR);
  assert.equal(provider.queries.length, 2);
});

test("the monthly allowance is never exceeded, and the watch waits instead of being lost", async () => {
  const { db, quota, provider } = setup(2);
  createWatch(db, "default", trip, NOW, 3);
  for (let i = 0; i < 4; i++) await checkDueWatches(db, provider, quota, NOW + i * 12 * HOUR);
  assert.equal(provider.queries.length, 2, "only two searches were allowed this month");
  assert.equal(quota.used(NOW), 2);
  const summary = await checkDueWatches(db, provider, quota, NOW + 5 * 12 * HOUR);
  assert.equal(summary.skippedNoQuota, 1);
  assert.equal(listWatches(db, "default").length, 1, "still watching");
  // A new month starts fresh.
  const nextMonth = Date.parse("2026-11-01T09:00:00Z");
  assert.equal((await checkDueWatches(db, provider, quota, nextMonth)).checked, 1);
});

test("a failed search is retried in an hour, not abandoned", async () => {
  const { db, quota, provider } = setup();
  createWatch(db, "default", trip, NOW, 3);
  provider.fail = true;
  const summary = await checkDueWatches(db, provider, quota, NOW);
  assert.equal(summary.failed, 1);
  assert.equal(listWatches(db, "default")[0].nextRunAt, NOW + HOUR);
  provider.fail = false;
  provider.priceMinor = 80_000;
  assert.equal((await checkDueWatches(db, provider, quota, NOW + HOUR)).alerts, 1);
});

test("watches for flights that have already left are retired", async () => {
  const { db, quota, provider } = setup();
  createWatch(db, "default", { ...trip, departDate: "2026-10-01" }, NOW, 3);
  const summary = await checkDueWatches(db, provider, quota, NOW);
  assert.equal(summary.expired, 1);
  assert.equal(provider.queries.length, 0, "no search is spent on a flight in the past");
  assert.equal(listWatches(db, "default").length, 0);
});

test("limits: number of watches, stopping, and what a watch costs", () => {
  const { db } = setup();
  createWatch(db, "default", trip, NOW, 2);
  const second = createWatch(db, "default", { ...trip, destination: "KRK" }, NOW, 2);
  assert.throws(() => createWatch(db, "default", trip, NOW, 2), /limit \(2\)/);
  assert.equal(stopWatch(db, "default", second.id), true);
  assert.equal(stopWatch(db, "default", second.id), false);
  createWatch(db, "default", trip, NOW, 2); // room again
  assert.equal(searchesPerMonth(12), 60);
  assert.equal(searchesPerMonth(24), 30);
});

test("watches belong to a user", () => {
  const { db } = setup();
  const watch = createWatch(db, "default", trip, NOW, 3);
  assert.equal(stopWatch(db, "someone-else", watch.id), false);
  assert.equal(listWatches(db, "someone-else").length, 0);
});
