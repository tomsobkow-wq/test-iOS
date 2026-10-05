import { test, after, before } from "node:test";
import assert from "node:assert/strict";
import type { AddressInfo } from "node:net";
import { createApp } from "../src/server.ts";
import { NOW, setup } from "./helpers.ts";

const ctx = setup(5);
const server = createApp({ config: ctx.config, db: ctx.db, quota: ctx.quota, provider: ctx.provider, now: () => NOW });
let base = "";
const headers = { authorization: "Bearer test-token-0123456789", "content-type": "application/json" };

before(async () => { await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve)); base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`; });
after(() => server.close());

const call = async (name: string, args: unknown, extra: Record<string, string> = {}) =>
  (await fetch(`${base}/v1/tools/call`, { method: "POST", headers: { ...headers, ...extra }, body: JSON.stringify({ name, arguments: args }) })).json() as Promise<{ ok: boolean; content: string }>;
const AU = { "x-country": "AU", "x-language": "en-AU", "x-currency": "aud" };
const PL = { "x-country": "PL", "x-language": "pl", "x-currency": "PLN" };

test("health is open, everything else needs the token", async () => {
  assert.equal((await fetch(`${base}/healthz`)).status, 200);
  assert.equal((await fetch(`${base}/v1/tools`)).status, 401);
  assert.equal((await fetch(`${base}/v1/tools`, { headers: { authorization: "Bearer wrong-token-0123456789" } })).status, 401);
  assert.equal((await fetch(`${base}/v1/tools`, { headers })).status, 200);
});

test("the app can discover the tools", async () => {
  const { tools } = await (await fetch(`${base}/v1/tools`, { headers })).json() as { tools: Array<{ name: string; parameters: { type: string } }> };
  assert.deepEqual(tools.map((t) => t.name), ["search_flights", "watch_flight_price", "search_products", "watch_product_price", "search_news", "watch_news", "web_search", "read_page", "list_watches", "stop_watch"]);
  assert.ok(tools.every((t) => t.parameters.type === "object"));
  const risks = Object.fromEntries((await (await fetch(`${base}/v1/tools`, { headers })).json() as { tools: Array<{ name: string; risk: string }> }).tools.map((t) => [t.name, t.risk]));
  assert.deepEqual(risks, { search_flights: "read", watch_flight_price: "write", search_products: "read", watch_product_price: "write", search_news: "read", watch_news: "write", web_search: "read", read_page: "read", list_watches: "read", stop_watch: "write" });
});

test("a flight search works with city names and returns the facts", async () => {
  ctx.provider.priceMinor = 84_200;
  const result = await call("search_flights", { origin: "Warszawa", destination: "Lizbona", depart_date: "2026-11-14" }, PL);
  assert.equal(result.ok, true);
  assert.match(result.content, /WAW -> LIS/);
  assert.match(result.content, /842\.00 PLN/);
  assert.equal(ctx.provider.queries.at(-1)?.currency, "PLN", "the phone's currency is the default");
  const perth = await call("search_flights", { origin: "Perth", destination: "SYD", depart_date: "2026-11-14" }, AU);
  assert.equal(perth.ok, true, perth.content);
  assert.match(perth.content, /PER -> SYD/);
  assert.equal(ctx.provider.queries.at(-1)?.currency, "AUD", "an Australian phone gets Australian dollars without saying so");
  await call("search_flights", { origin: "Perth", destination: "SYD", depart_date: "2026-11-14", currency: "EUR" }, AU);
  assert.equal(ctx.provider.queries.at(-1)?.currency, "EUR", "but the user can ask for another currency");
});

test("arguments may arrive as a JSON string, as models often send them", async () => {
  const result = await call("search_flights", '{"origin":"WAW","destination":"KRK","depart_date":"2026-12-01"}');
  assert.equal(result.ok, true);
});

test("problems the model can fix come back as readable text", async () => {
  assert.match((await call("search_flights", { origin: "WAW", destination: "LIS" })).content, /depart_date are required/);
  assert.match((await call("search_flights", { origin: "WAW", destination: "LIS", depart_date: "2026-09-01" })).content, /in the past/);
  assert.match((await call("search_flights", { origin: "Zielona Góra", destination: "LIS", depart_date: "2026-11-14" })).content, /airport code/);
  assert.match((await call("search_flights", { origin: "WAW", destination: "LIS", depart_date: "14 listopada" })).content, /YYYY-MM-DD/);
  assert.equal((await call("search_flights", { origin: "WAW", destination: "LIS", depart_date: "2026-11-14", return_date: "2026-11-01" })).ok, false);
});

test("watching: create, list, alert, stop", async () => {
  const created = await call("watch_flight_price", { origin: "WAW", destination: "LIS", depart_date: "2026-11-14", max_price: 900 });
  assert.equal(created.ok, true);
  assert.match(created.content, /about 60 of the 5 flight searches/); // limit is 5 in this test setup
  const listed = await call("list_watches", {});
  const id = /\[([0-9a-f]{8})\]/.exec(listed.content)?.[1];
  assert.ok(id, listed.content);
  assert.equal((await call("watch_flight_price", { origin: "WAW", destination: "LIS", depart_date: "2026-11-14" })).ok, false, "max_price is required");
  assert.match((await call("stop_watch", { id })).content, /Stopped/);
  assert.match((await call("list_watches", {})).content, /No active watches/);
});

test("alerts are served and can be marked seen", async () => {
  const { checkDueWatches, createWatch } = await import("../src/watches.ts");
  createWatch(ctx.db, "default", { origin: "WAW", destination: "ROM", departDate: "2026-12-10", adults: 1, currency: "PLN", thresholdMinor: 100_000, everyHours: 12 }, NOW, 5);
  ctx.provider.priceMinor = 70_000;
  await checkDueWatches(ctx.db, ctx.provider, ctx.quota, NOW);
  const { alerts } = await (await fetch(`${base}/v1/alerts?since=0`, { headers })).json() as { alerts: Array<{ id: number; title: string; seen: boolean }> };
  assert.equal(alerts.length, 1);
  assert.match(alerts[0].title, /WAW to ROM/);
  await fetch(`${base}/v1/alerts/seen`, { method: "POST", headers, body: JSON.stringify({ upTo: alerts[0].id }) });
  const after = await (await fetch(`${base}/v1/alerts?since=${alerts[0].id}`, { headers })).json() as { alerts: unknown[] };
  assert.equal(after.alerts.length, 0, "since= returns only newer alerts");
});

test("unknown tools and bad bodies are refused", async () => {
  assert.equal((await fetch(`${base}/v1/tools/call`, { method: "POST", headers, body: JSON.stringify({ name: "rm_rf", arguments: {} }) })).status, 404);
  assert.equal((await fetch(`${base}/v1/tools/call`, { method: "POST", headers, body: "not json" })).status, 400);
  assert.equal((await fetch(`${base}/v1/tools/call`, { method: "POST", headers, body: JSON.stringify({ name: "list_watches", arguments: [1] }) })).status, 400);
});

test("with no flight key the tools say so plainly", async () => {
  const bare = createApp({ config: ctx.config, db: ctx.db, quota: ctx.quota, provider: undefined, now: () => NOW });
  await new Promise<void>((r) => bare.listen(0, "127.0.0.1", r));
  const url = `http://127.0.0.1:${(bare.address() as AddressInfo).port}/v1/tools/call`;
  const answer = await (await fetch(url, { method: "POST", headers, body: JSON.stringify({ name: "search_flights", arguments: { origin: "WAW", destination: "LIS", depart_date: "2026-11-14" } }) })).json() as { ok: boolean; content: string };
  assert.equal(answer.ok, false);
  assert.match(answer.content, /not set up on the server/);
  bare.close();
});

test("a locale header from the phone is read, and anything malformed is ignored", async () => {
  const { localeFrom } = await import("../src/server.ts");
  const req = (h: Record<string, string>) => ({ headers: h }) as never;
  assert.deepEqual(localeFrom(req({ "x-country": "AU", "x-language": "en", "x-currency": "aud" })), { country: "au", language: "en", currency: "AUD" });
  assert.deepEqual(localeFrom(req({ "x-country": "au" })), { country: "au", language: "en", currency: "AUD" }, "missing parts are filled in from the country");
  assert.equal(localeFrom(req({ "x-country": "australia" })), undefined);
  assert.equal(localeFrom(req({})), undefined);
  assert.equal(localeFrom(req({ "x-country": "au", "x-language": "<script>", "x-currency": "dollars" }))?.language, "en");
});
