import { test } from "node:test";
import assert from "node:assert/strict";
import { parseShopping, relevantOffers, describeProducts, currencyFor, serpApiShoppingURL } from "../src/shopping.ts";
import { parseNews, parseNewsDate, describeNews, serpApiNewsURL } from "../src/news.ts";
import { checkDueTopicWatches, createTopicWatch, listTopicWatches, stopTopicWatch, countActiveWatches } from "../src/topicWatches.ts";
import { createWatch } from "../src/watches.ts";
import { TtlCache } from "../src/cache.ts";
import { tools, type ToolContext } from "../src/tools.ts";
import { NOW, setup } from "./helpers.ts";
import { FakeNews, FakeShopping, item, offer } from "./helpers2.ts";

const HOUR = 3_600_000;

test("shopping results are read into prices in minor units with the right currency", () => {
  const offers = parseShopping({
    shopping_results: [
      { title: "Rower elektryczny Villette", price: "3399,99 zł", extracted_price: 3399.99, source: "Media Expert", product_link: "https://x/1", rating: 2.3, reviews: 14, product_id: 123 },
      { title: "No price", source: "Shop" },
      { title: "Euro bike", price: "€1,299.00", extracted_price: 1299, source: "Shop", link: "https://x/2" },
    ],
  }, "pl");
  assert.equal(offers.length, 2);
  assert.deepEqual([offers[0].priceMinor, offers[0].currency, offers[0].shop, offers[0].productId], [339_999, "PLN", "Media Expert", "123"]);
  assert.equal(offers[1].currency, "EUR");
  assert.deepEqual(parseShopping({ error: "Google hasn't returned any results for this search." }, "pl"), []);
  assert.throws(() => parseShopping({ error: "Invalid API key" }, "pl"), /Product search failed/);
  assert.equal(currencyFor("de"), "EUR");
  assert.equal(currencyFor("pl"), "PLN");
});

test("the shopping request carries country, language and the price ceiling", () => {
  const url = new URL(serpApiShoppingURL({ query: "rower elektryczny", country: "pl", language: "pl", maxPriceMajor: 5000 }, "KEY"));
  assert.equal(url.searchParams.get("engine"), "google_shopping");
  assert.deepEqual([url.searchParams.get("gl"), url.searchParams.get("hl"), url.searchParams.get("max_price")], ["pl", "pl", "5000"]);
});

test("relevance drops accessories and wrong models", () => {
  const offers = [offer("Rower elektryczny Touroll Urbano 3", 466_900), offer("Bateria do roweru Touroll", 90_000), offer("Rower elektryczny Touroll Urbano 4", 480_000), offer("Hulajnoga", 10_000)];
  const kept = relevantOffers("rower elektryczny Touroll Urbano 3", offers).map((o) => o.title);
  assert.deepEqual(kept, ["Rower elektryczny Touroll Urbano 3"], "a model number must match exactly");
  assert.deepEqual(relevantOffers("rower elektryczny", offers).map((o) => o.title), ["Rower elektryczny Touroll Urbano 3", "Rower elektryczny Touroll Urbano 4"], "a plain query keeps the real bikes and drops the battery and the scooter");
});

test("accessories that borrow the product's name, and far-too-cheap listings, are dropped", () => {
  const bike = (n: number, price: number) => offer(`Rower elektryczny Model ${n}`, price);
  const kept = relevantOffers("rower elektryczny", [bike(1, 400_000), bike(2, 420_000), bike(3, 380_000), bike(4, 450_000), offer("Rower elektryczny naklejka", 900), offer("Rower elektryczny Torba na ramę", 12_000), offer("Rower elektryczny Model 9", 15_000)]);
  assert.equal(kept.length, 4, kept.map((o) => o.title).join(" | "));
  const asked = relevantOffers("bateria do roweru elektrycznego", [offer("Bateria do roweru elektrycznego 36V", 90_000)]);
  assert.equal(asked.length, 1, "asking for a battery still finds batteries");
});

test("products come back cheapest first with ratings and a caution about shipping", () => {
  const text = describeProducts({ query: "rower elektryczny", country: "pl", language: "pl", maxPriceMajor: 5000 }, [offer("Bike B", 400_000, "Allegro", { rating: 4.5, reviews: 10 }), offer("Bike A", 330_000, "Decathlon")]);
  assert.ok(text.indexOf("Bike A") < text.indexOf("Bike B"));
  assert.match(text, /rating 4\.5 \(10 reviews\)/);
  assert.match(text, /up to 5000/);
  assert.match(text, /Shipping may not be included/);
  assert.ok(!text.includes("http"), "long shop links only waste the model's reading time");
});

test("news dates are read, clusters are flattened and the newest comes first", () => {
  assert.equal(parseNewsDate("10/05/2026, 07:54 AM, +0000 UTC"), "2026-10-05T07:54:00.000Z");
  assert.equal(parseNewsDate("10/05/2026, 12:13 PM, +0000 UTC"), "2026-10-05T12:13:00.000Z");
  assert.equal(parseNewsDate("10/05/2026, 12:13 AM, +0000 UTC"), "2026-10-05T00:13:00.000Z");
  assert.equal(parseNewsDate("garbage"), null);
  const items = parseNews({
    news_results: [
      { title: "Top news", stories: [{ title: "Older story", link: "https://a/1", source: { name: "Sky News" }, date: "10/05/2026, 12:13 AM, +0000 UTC" }, { title: "Newer story", link: "https://a/2", source: { name: "The Guardian" }, date: "10/05/2026, 05:11 AM, +0000 UTC" }] },
      { title: "Plain item", link: "https://a/3", source: "reuters.com", date: "10/05/2026, 06:02 AM, +0000 UTC" },
      { title: "Duplicate", link: "https://a/3", source: "reuters.com" },
      { title: "No link" },
    ],
  });
  assert.deepEqual(items.map((i) => i.title), ["Plain item", "Newer story", "Older story"]);
  assert.equal(items[1].source, "The Guardian");
  assert.deepEqual(parseNews({ error: "Google hasn't returned any results for this query." }), []);
  assert.equal(new URL(serpApiNewsURL({ query: "x", country: "pl", language: "pl" }, "K")).searchParams.get("engine"), "google_news");
});

test("the news text tells the model to cite outlets and times and not to invent", () => {
  const text = describeNews({ query: "war in Ukraine", country: "us", language: "en" }, [item("Talks proposed", "https://a/1", "Sky News", "2026-10-05T07:00:00.000Z")], Date.parse("2026-10-05T09:00:00Z"));
  assert.match(text, /\[2026-10-05 07:00 UTC, 2 h ago\] Sky News: Talks proposed/);
  assert.match(text, /only from these headlines/);
  assert.match(text, /disputed/);
  assert.ok(!text.includes("https://"), "raw addresses only clutter the answer");
});

test("a product watch alerts at or below the limit, once per price, and only for the right product", async () => {
  const { db, quota } = setup();
  const shopping = new FakeShopping();
  createTopicWatch(db, "default", { kind: "product", query: "Touroll Urbano 3", country: "pl", language: "pl", currency: "PLN", thresholdMinor: 450_000, everyHours: 12 }, NOW, 5);
  shopping.offers = [offer("Rower Touroll Urbano 3", 466_900, "Empik"), offer("Torba do Touroll Urbano 3", 9_000)];
  let summary = await checkDueTopicWatches(db, { shopping }, quota, NOW);
  assert.deepEqual([summary.checked, summary.alerts], [1, 0], "466.90 is above the 450 limit; the 90 zł bag is not the product");
  assert.equal(listTopicWatches(db, "default")[0].lastPriceMinor, 466_900);

  shopping.offers = [offer("Rower Touroll Urbano 3", 439_000, "Decathlon")];
  summary = await checkDueTopicWatches(db, { shopping }, quota, NOW + 12 * HOUR);
  assert.equal(summary.alerts, 1);
  summary = await checkDueTopicWatches(db, { shopping }, quota, NOW + 24 * HOUR);
  assert.equal(summary.alerts, 0, "the same price is not announced again");
  shopping.offers = [offer("Rower Touroll Urbano 3", 419_000, "Decathlon")];
  assert.equal((await checkDueTopicWatches(db, { shopping }, quota, NOW + 36 * HOUR)).alerts, 1);
  const alerts = db.prepare("SELECT title, body FROM alerts ORDER BY id").all() as Array<{ title: string; body: string }>;
  assert.match(alerts[0].title, /Price drop: Touroll Urbano 3/);
  assert.match(alerts[0].body, /4390\.00 PLN at Decathlon \(your limit 4500\.00 PLN\)/);
});

test("a news watch starts quiet, then alerts only on headlines it has not shown before", async () => {
  const { db, quota } = setup();
  const news = new FakeNews();
  createTopicWatch(db, "default", { kind: "news", query: "war in Ukraine", country: "us", language: "en", everyHours: 6 }, NOW, 5);
  news.items = [item("Old 1", "https://a/1"), item("Old 2", "https://a/2")];
  assert.equal((await checkDueTopicWatches(db, { news }, quota, NOW)).alerts, 0, "the first check only learns what is already out");
  assert.equal((await checkDueTopicWatches(db, { news }, quota, NOW + 6 * HOUR)).alerts, 0, "nothing new, nothing said");
  news.items = [item("Fresh", "https://a/3", "BBC"), item("Old 1", "https://a/1")];
  assert.equal((await checkDueTopicWatches(db, { news }, quota, NOW + 12 * HOUR)).alerts, 1);
  assert.equal((await checkDueTopicWatches(db, { news }, quota, NOW + 18 * HOUR)).alerts, 0, "the same headline is not repeated");
  const alert = db.prepare("SELECT title, body FROM alerts").get() as { title: string; body: string };
  assert.match(alert.title, /News: war in Ukraine/);
  assert.match(alert.body, /1 new headline\. BBC: Fresh/);
});

test("topic watches respect the monthly allowance, retry after failures and can be stopped", async () => {
  const { db, quota } = setup(1);
  const shopping = new FakeShopping();
  const watch = createTopicWatch(db, "default", { kind: "product", query: "x y", country: "pl", language: "pl", currency: "PLN", thresholdMinor: 100, everyHours: 6 }, NOW, 5);
  quota.consume(NOW);
  assert.equal((await checkDueTopicWatches(db, { shopping }, quota, NOW)).skippedNoQuota, 1);
  const { db: db2, quota: quota2 } = setup(10);
  createTopicWatch(db2, "default", { kind: "product", query: "x y", country: "pl", language: "pl", currency: "PLN", thresholdMinor: 100, everyHours: 6 }, NOW, 5);
  shopping.fail = true;
  assert.equal((await checkDueTopicWatches(db2, { shopping }, quota2, NOW)).failed, 1);
  assert.equal(listTopicWatches(db2, "default")[0].nextRunAt, NOW + HOUR);
  assert.equal(stopTopicWatch(db, "default", watch.id), true);
  assert.equal(listTopicWatches(db, "default").length, 0);
});

test("flight, product and news watches share one limit", () => {
  const { db } = setup();
  createWatch(db, "default", { origin: "WAW", destination: "LIS", departDate: "2026-11-14", adults: 1, currency: "PLN", thresholdMinor: 90_000, everyHours: 12 }, NOW, 2);
  createTopicWatch(db, "default", { kind: "news", query: "a b", country: "pl", language: "pl", everyHours: 6 }, NOW, 2);
  assert.equal(countActiveWatches(db, "default"), 2);
  assert.throws(() => createTopicWatch(db, "default", { kind: "product", query: "c d", country: "pl", language: "pl", currency: "PLN", thresholdMinor: 1, everyHours: 6 }, NOW, 2), /limit/);
});

test("the ttl cache expires and stays bounded", () => {
  const cache = new TtlCache<number>(1000, 2);
  cache.set("a", 1, 0); cache.set("b", 2, 0); cache.set("c", 3, 0);
  assert.equal(cache.get("a", 10), undefined, "oldest entry makes room");
  assert.equal(cache.get("c", 10), 3);
  assert.equal(cache.get("c", 1001), undefined, "expired");
});

function toolContext(extra: Partial<ToolContext> = {}): { ctx: ToolContext; shopping: FakeShopping; news: FakeNews; limit: number } {
  const base = setup(5);
  const shopping = new FakeShopping(), news = new FakeNews();
  const ctx: ToolContext = {
    db: base.db, config: { ...base.config, maxWatches: 5 }, quota: base.quota, provider: undefined, shopping, news,
    caches: { products: new TtlCache(600_000), news: new TtlCache(300_000), web: new TtlCache(600_000), recentWeb: new TtlCache(1_800_000) }, defaults: { country: "pl", language: "pl", currency: "PLN" }, user: "default", now: () => NOW, ...extra,
  };
  return { ctx, shopping, news, limit: 5 };
}
const tool = (name: string) => tools.find((t) => t.name === name)!;

test("search_products answers from a cache the second time and filters by relevance", async () => {
  const { ctx, shopping } = toolContext();
  shopping.offers = [offer("Rower elektryczny A", 300_000), offer("Pompka do roweru", 5_000)];
  const first = await tool("search_products").run({ query: "rower elektryczny", max_price: 5000 }, ctx);
  assert.match(first, /1 offers found/);
  assert.equal(shopping.queries[0].maxPriceMajor, 5000);
  assert.equal(shopping.queries[0].country, "pl");
  await tool("search_products").run({ query: "rower elektryczny", max_price: 5000 }, ctx);
  assert.equal(shopping.queries.length, 1, "the repeat was served from the cache");
  assert.equal(ctx.quota.used(NOW), 1, "and cost no second search");
});

test("an Australian phone searches Australian shops in dollars without being told", async () => {
  const au = { country: "au", language: "en", currency: "AUD" };
  const { ctx, shopping, news } = toolContext({ defaults: au });
  shopping.offers = [offer("Electric bike 36V", 199_900, "Kogan", { currency: "AUD" })];
  const text = await tool("search_products").run({ query: "electric bike", max_price: 2000 }, ctx);
  assert.deepEqual([shopping.queries[0].country, shopping.queries[0].language], ["au", "en"]);
  assert.match(text, /1999\.00 AUD \| Kogan/);
  news.items = [item("Headline", "https://a/1")];
  await tool("search_news").run({ query: "interest rates" }, ctx);
  assert.deepEqual([news.queries[0].country, news.queries[0].language], ["au", "en"]);
  const watch = await tool("watch_product_price").run({ query: "Dyson V15", max_price: 900 }, ctx);
  assert.match(watch, /at or below 900\.00 AUD/);
  const other = await tool("search_products").run({ query: "kielbasa", country: "pl", language: "pl" }, ctx);
  assert.ok(other);
  assert.deepEqual([shopping.queries.at(-1)?.country, shopping.queries.at(-1)?.language], ["pl", "pl"], "naming another country still works");
});

test("a bare dollar sign is the dollar of the shopper's own country", () => {
  assert.equal(currencyFor("au", "$1,299.00"), "AUD");
  assert.equal(currencyFor("nz", "$899"), "NZD");
  assert.equal(currencyFor("ca", "$50"), "CAD");
  assert.equal(currencyFor("us", "$20"), "USD");
  assert.equal(currencyFor("au", "US$20"), "USD");
  assert.equal(currencyFor("au", "A$1,299.00"), "AUD");
  assert.equal(currencyFor("pl", "$20"), "USD", "a dollar price in a non-dollar country is US dollars");
  assert.equal(currencyFor("au", ""), "AUD");
  assert.equal(currencyFor("zz", ""), "USD");
});

test("search_news is cached and spends one search per topic", async () => {
  const { ctx, news } = toolContext();
  news.items = [item("Headline", "https://a/1")];
  const text = await tool("search_news").run({ query: "war in Ukraine", country: "us", language: "en" }, ctx);
  assert.match(text, /Reuters: Headline/);
  await tool("search_news").run({ query: "war in Ukraine", country: "us", language: "en" }, ctx);
  await tool("search_news").run({ query: "war in Ukraine", country: "pl", language: "pl" }, ctx);
  assert.equal(news.queries.length, 2, "a different country and language is a different search");
  assert.equal(ctx.quota.used(NOW), 2);
});

test("the tools refuse bad input and say plainly when the allowance or the key is missing", async () => {
  const { ctx } = toolContext();
  await assert.rejects(tool("search_products").run({}, ctx), /query is required/);
  await assert.rejects(tool("search_news").run({ query: "x", country: "poland" }, ctx), /two letters/);
  await assert.rejects(tool("watch_product_price").run({ query: "Touroll Urbano 3" }, ctx), /max_price/);
  await assert.rejects(tool("search_products").run({ query: "x" }, { ...ctx, shopping: undefined }), /not set up/);
  await assert.rejects(tool("search_news").run({ query: "x" }, { ...ctx, news: undefined }), /not set up/);
  const spent = toolContext();
  for (let i = 0; i < 5; i++) spent.ctx.quota.consume(NOW);
  await assert.rejects(tool("search_news").run({ query: "fresh topic" }, spent.ctx), /allowance/);
});

test("watch tools create, list and stop every kind of watch", async () => {
  const { ctx } = toolContext();
  const product = await tool("watch_product_price").run({ query: "Touroll Urbano 3", max_price: 4500 }, ctx);
  assert.match(product, /alert at or below 4500\.00 PLN/);
  const follow = await tool("watch_news").run({ query: "war in Ukraine", country: "us", language: "en", every_hours: 1 }, ctx);
  assert.match(follow, /checked every 3h/, "news is never checked more often than every 3 hours");
  const listed = await tool("list_watches").run({}, ctx);
  assert.match(listed, /product "Touroll Urbano 3"/);
  assert.match(listed, /news on "war in Ukraine"/);
  assert.match(listed, /Watches active: 2 of 5/);
  const id = /\[([0-9a-f]{8})\] news/.exec(listed)?.[1];
  assert.ok(id);
  assert.match(await tool("stop_watch").run({ id }, ctx), /Stopped/);
  assert.match(await tool("stop_watch").run({ id }, ctx), /no active watch/);
});
