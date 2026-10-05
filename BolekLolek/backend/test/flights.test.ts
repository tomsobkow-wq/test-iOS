import { test } from "node:test";
import assert from "node:assert/strict";
import { describeResult, parseSerpApi, serpApiURL, SerpApiFlights } from "../src/flights.ts";
import { resolveAirport } from "../src/airports.ts";

// Shaped like SerpApi's documented google_flights response.
const sample = {
  best_flights: [{
    flights: [{ departure_airport: { name: "Warsaw Chopin", id: "WAW", time: "2026-11-14 06:15" }, arrival_airport: { name: "Humberto Delgado", id: "LIS", time: "2026-11-14 10:20" }, duration: 245, airline: "TAP Air Portugal", flight_number: "TP 1235" }],
    total_duration: 245, price: 842,
  }],
  other_flights: [
    { flights: [
      { departure_airport: { id: "WAW", time: "2026-11-14 07:00" }, arrival_airport: { id: "FRA", time: "2026-11-14 08:50" }, duration: 110, airline: "Lufthansa", flight_number: "LH 1363" },
      { departure_airport: { id: "FRA", time: "2026-11-14 10:30" }, arrival_airport: { id: "LIS", time: "2026-11-14 12:55" }, duration: 205, airline: "Lufthansa", flight_number: "LH 1174" }], total_duration: 415, price: 799.5 },
    { flights: [], price: 100 },            // no legs: ignored
    { flights: [{ airline: "X" }] },        // no price: ignored
  ],
  price_insights: { lowest_price: 799, price_level: "low", typical_price_range: [900, 1300] },
};

test("offers are parsed, cleaned and sorted cheapest first", () => {
  const result = parseSerpApi(sample, "PLN");
  assert.deepEqual(result.offers.map((o) => o.priceMinor), [79_950, 84_200]);
  assert.equal(result.offers[0].stops, 1);
  assert.deepEqual(result.offers[0].airlines, ["Lufthansa"]);
  assert.equal(result.offers[1].stops, 0);
  assert.deepEqual(result.offers[1].flightNumbers, ["TP 1235"]);
  assert.equal(result.priceLevel, "low");
  assert.deepEqual(result.typicalRangeMinor, [90_000, 130_000]);
});

test("the text for the model has the facts and a caveat", () => {
  const query = { origin: "WAW", destination: "LIS", departDate: "2026-11-14", adults: 1, currency: "PLN" };
  const text = describeResult(query, parseSerpApi(sample, "PLN"));
  assert.match(text, /WAW -> LIS, 2026-11-14 \(one way\), 1 adult/);
  assert.match(text, /1\. 799\.50 PLN \| Lufthansa \| 1 stop \| 6h55/);
  assert.match(text, /2\. 842\.00 PLN \| TAP Air Portugal \| direct \| 4h05/);
  assert.match(text, /Google says this price is low; typical range 900\.00 PLN to 1300\.00 PLN/);
  assert.match(text, /not a booking/);
});

test("no results is an answer, an API error is an error", () => {
  assert.deepEqual(parseSerpApi({ error: "Google Flights hasn't returned any results for this query." }, "PLN").offers, []);
  assert.throws(() => parseSerpApi({ error: "Invalid API key. Your API key should be here: https://serpapi.com/manage-api-key" }, "PLN"), /Flight search failed/);
});

test("the request asks for a one way or round trip as needed", () => {
  const base = { origin: "WAW", destination: "LIS", departDate: "2026-11-14", adults: 2, currency: "PLN" };
  const oneWay = new URL(serpApiURL(base, "KEY"));
  assert.equal(oneWay.searchParams.get("engine"), "google_flights");
  assert.equal(oneWay.searchParams.get("type"), "2");
  assert.equal(oneWay.searchParams.get("return_date"), null);
  assert.equal(oneWay.searchParams.get("adults"), "2");
  const round = new URL(serpApiURL({ ...base, returnDate: "2026-11-20", maxPriceMajor: 1000 }, "KEY"));
  assert.equal(round.searchParams.get("type"), "1");
  assert.equal(round.searchParams.get("return_date"), "2026-11-20");
  assert.equal(round.searchParams.get("max_price"), "1000");
});

test("the provider calls SerpApi and parses the answer, and survives a bad one", async () => {
  const urls: string[] = [];
  const provider = new SerpApiFlights("KEY", async (url) => { urls.push(url); return { ok: true, status: 200, json: async () => sample }; });
  const result = await provider.search({ origin: "WAW", destination: "LIS", departDate: "2026-11-14", adults: 1, currency: "PLN" });
  assert.equal(result.offers.length, 2);
  assert.match(urls[0], /^https:\/\/serpapi\.com\/search\?/);
  const broken = new SerpApiFlights("KEY", async () => ({ ok: false, status: 502, json: async () => { throw new Error("html"); } }));
  await assert.rejects(broken.search({ origin: "WAW", destination: "LIS", departDate: "2026-11-14", adults: 1, currency: "PLN" }), /Flight search failed/);
});

test("airports: codes, Polish and English city names, diacritics, unknowns", () => {
  assert.deepEqual(resolveAirport("waw"), { code: "WAW" });
  assert.deepEqual(resolveAirport("Warszawa"), { code: "WAW" });
  assert.deepEqual(resolveAirport("Kraków"), { code: "KRK" });
  assert.deepEqual(resolveAirport("Gdańsk"), { code: "GDN" });
  assert.deepEqual(resolveAirport("Lizbona"), { code: "LIS" });
  assert.deepEqual(resolveAirport("New York"), { code: "NYC" });
  assert.deepEqual(resolveAirport("Łódź"), { code: "LCJ" });
  const unknown = resolveAirport("Zielona Góra");
  assert.ok("error" in unknown && /3-letter IATA airport code/.test(unknown.error));
});

test("Australian and other world cities resolve, and any 3-letter code is accepted as it is", () => {
  for (const [name, code] of [["Perth", "PER"], ["Sydney", "SYD"], ["Gold Coast", "OOL"], ["Auckland", "AKL"], ["Singapore", "SIN"], ["perth", "PER"]] as const) {
    assert.deepEqual(resolveAirport(name), { code }, name);
  }
  assert.deepEqual(resolveAirport("dps"), { code: "DPS" });
});
