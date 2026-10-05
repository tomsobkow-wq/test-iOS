// Product offers from Google Shopping, through SerpApi (https://serpapi.com/google-shopping-api).
import { overlap, words } from "./text.ts";
import type { FetchFn } from "./flights.ts";
import { money } from "./flights.ts";

export interface ProductQuery {
  query: string;
  country: string;       // two letters, "pl"
  language: string;      // "pl", "en"
  minPriceMajor?: number;
  maxPriceMajor?: number;
}

export interface ProductOffer {
  title: string;
  priceMinor: number;
  currency: string;
  shop: string;
  link: string;
  rating?: number;
  reviews?: number;
  productId?: string;
}

const CURRENCY_BY_COUNTRY: Record<string, string> = { pl: "PLN", us: "USD", gb: "GBP", uk: "GBP", de: "EUR", fr: "EUR", es: "EUR", it: "EUR", nl: "EUR", ie: "EUR", at: "EUR", pt: "EUR", cz: "CZK" };

export function currencyFor(country: string, priceText?: string): string {
  const text = priceText ?? "";
  if (/zł|PLN/i.test(text)) return "PLN";
  if (/€|EUR/i.test(text)) return "EUR";
  if (/£|GBP/i.test(text)) return "GBP";
  if (/Kč|CZK/i.test(text)) return "CZK";
  if (/\$|USD/i.test(text)) return "USD";
  return CURRENCY_BY_COUNTRY[country.toLowerCase()] ?? "USD";
}

export function serpApiShoppingURL(q: ProductQuery, apiKey: string): string {
  const params = new URLSearchParams({ engine: "google_shopping", q: q.query, gl: q.country, hl: q.language, api_key: apiKey });
  if (q.minPriceMajor) params.set("min_price", String(Math.round(q.minPriceMajor)));
  if (q.maxPriceMajor) params.set("max_price", String(Math.round(q.maxPriceMajor)));
  return `https://serpapi.com/search.json?${params}`;
}

type SerpProduct = {
  title?: string; price?: string; extracted_price?: number; source?: string; link?: string; product_link?: string;
  rating?: number; reviews?: number; product_id?: string | number;
};

export function parseShopping(json: unknown, country: string): ProductOffer[] {
  const body = json as { error?: string; shopping_results?: SerpProduct[] };
  if (body.error) {
    if (/hasn't returned any results|no results/i.test(body.error)) return [];
    throw new Error(`Product search failed: ${body.error}`);
  }
  const offers: ProductOffer[] = [];
  for (const item of body.shopping_results ?? []) {
    if (!item.title || typeof item.extracted_price !== "number" || item.extracted_price <= 0) continue;
    offers.push({
      title: item.title,
      priceMinor: Math.round(item.extracted_price * 100),
      currency: currencyFor(country, item.price),
      shop: item.source ?? "unknown shop",
      link: item.product_link ?? item.link ?? "",
      rating: item.rating,
      reviews: item.reviews,
      productId: item.product_id === undefined ? undefined : String(item.product_id),
    });
  }
  return offers;
}

export interface ProductProvider {
  search(query: ProductQuery): Promise<ProductOffer[]>;
}

export class SerpApiShopping implements ProductProvider {
  private apiKey: string;
  private fetchFn: FetchFn;

  constructor(apiKey: string, fetchFn: FetchFn = (url) => fetch(url)) {
    this.apiKey = apiKey;
    this.fetchFn = fetchFn;
  }

  async search(query: ProductQuery): Promise<ProductOffer[]> {
    const response = await this.fetchFn(serpApiShoppingURL(query, this.apiKey));
    const json = await response.json().catch(() => ({ error: `unreadable answer (HTTP ${response.status})` }));
    if (!response.ok && !(json as { error?: string }).error) throw new Error(`Product search failed (HTTP ${response.status}).`);
    return parseShopping(json, query.country);
  }
}

/** Words that mark a part or accessory. Offers with them are dropped unless the user asked for that kind of item. */
const ACCESSORY_WORDS = [
  "torba", "torbe", "sakwa", "sakwy", "bateria", "baterie", "akumulator", "ladowarka", "pokrowiec", "etui", "uchwyt", "opona", "opony", "detka", "kask", "koszyk",
  "lampka", "lampa", "blotnik", "siodelko", "pedaly", "lancuch", "zamek", "dzwonek", "pompka", "naklejka", "folia", "szybka", "czesci", "czesc",
  "charger", "cover", "case", "strap", "holder", "mount", "tyre", "tire", "helmet", "spare", "replacement", "sticker", "protector",
];

/**
 * Keeps the offers that are really for what was asked: most of the query's words must be in the title, which drops
 * unrelated listings Google mixes in; a model number (any word with a digit) must always be present; parts and accessories
 * that borrow the product's name (a bag "for" the bike) are dropped; and when there are enough offers, anything priced far
 * below the typical price is treated as an accessory too.
 */
export function relevantOffers(query: string, offers: ProductOffer[], minimumOverlap = 0.6): ProductOffer[] {
  const wanted = words(query);
  const numbers = wanted.filter((w) => /\d/.test(w));
  const asked = new Set(wanted);
  const kept = offers.filter((o) => {
    if (overlap(wanted, o.title) < minimumOverlap) return false;
    if (numbers.length > 0 && overlap(numbers, o.title) !== 1) return false;
    return !words(o.title).some((w) => ACCESSORY_WORDS.includes(w) && !asked.has(w));
  });
  if (kept.length >= 4) {
    const prices = kept.map((o) => o.priceMinor).sort((a, b) => a - b);
    const median = prices[Math.floor(prices.length / 2)];
    return kept.filter((o) => o.priceMinor >= median * 0.3);
  }
  return kept;
}

export function describeProducts(query: ProductQuery, offers: ProductOffer[], limit = 6): string {
  const label = `"${query.query}"${query.maxPriceMajor ? ` up to ${query.maxPriceMajor}` : ""}`;
  if (offers.length === 0) return `No products found for ${label}.`;
  const cheapest = [...offers].sort((a, b) => a.priceMinor - b.priceMinor).slice(0, limit);
  const lines = [`${offers.length} offers found for ${label}. Cheapest first:`];
  cheapest.forEach((o, i) => {
    const rating = o.rating ? ` | rating ${o.rating}${o.reviews ? ` (${o.reviews} reviews)` : ""}` : "";
    lines.push(`${i + 1}. ${money(o.priceMinor, o.currency)} | ${o.shop} | ${o.title.slice(0, 90)}${rating}`);
  });
  lines.push("Prices come from Google Shopping and can change; a low price does not mean a good product, so mention ratings. Shipping may not be included.");
  return lines.join("\n");
}
