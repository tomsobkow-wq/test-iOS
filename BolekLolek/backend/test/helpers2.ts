import type { NewsItem, NewsProvider, NewsQuery } from "../src/news.ts";
import type { ProductOffer, ProductProvider, ProductQuery } from "../src/shopping.ts";

/** Product search that returns what the test sets and records every query. */
export class FakeShopping implements ProductProvider {
  offers: ProductOffer[] = [];
  queries: ProductQuery[] = [];
  fail = false;
  async search(query: ProductQuery): Promise<ProductOffer[]> {
    this.queries.push(query);
    if (this.fail) throw new Error("boom");
    return this.offers;
  }
}

export class FakeNews implements NewsProvider {
  items: NewsItem[] = [];
  queries: NewsQuery[] = [];
  fail = false;
  async search(query: NewsQuery): Promise<NewsItem[]> {
    this.queries.push(query);
    if (this.fail) throw new Error("boom");
    return this.items;
  }
}

export const offer = (title: string, priceMinor: number, shop = "Decathlon", extra: Partial<ProductOffer> = {}): ProductOffer =>
  ({ title, priceMinor, currency: "PLN", shop, link: `https://shop.example/${encodeURIComponent(title)}`, ...extra });

export const item = (title: string, link: string, source = "Reuters", publishedAt: string | null = "2026-10-05T07:00:00.000Z"): NewsItem =>
  ({ title, link, source, publishedAt });
