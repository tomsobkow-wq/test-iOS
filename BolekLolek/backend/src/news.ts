// Headlines from Google News, through SerpApi (https://serpapi.com/google-news-api).
import type { FetchFn } from "./flights.ts";

export interface NewsQuery {
  query: string;
  country: string;   // "pl", "us"
  language: string;  // "pl", "en"
}

export interface NewsItem {
  title: string;
  source: string;
  publishedAt: string | null;   // ISO 8601, UTC
  link: string;
  snippet?: string;
}

export function serpApiNewsURL(q: NewsQuery, apiKey: string): string {
  return `https://serpapi.com/search.json?${new URLSearchParams({ engine: "google_news", q: q.query, gl: q.country, hl: q.language, api_key: apiKey })}`;
}

/** "10/05/2026, 07:54 AM, +0000 UTC" (month/day/year) to ISO. Returns null when it cannot be read. */
export function parseNewsDate(text: string | undefined): string | null {
  if (!text) return null;
  const m = text.match(/^(\d{2})\/(\d{2})\/(\d{4}),\s*(\d{1,2}):(\d{2})\s*(AM|PM)/i);
  if (!m) return null;
  let hour = Number(m[4]) % 12;
  if (m[6].toUpperCase() === "PM") hour += 12;
  const date = new Date(Date.UTC(Number(m[3]), Number(m[1]) - 1, Number(m[2]), hour, Number(m[5])));
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

type SerpNews = { title?: string; link?: string; date?: string; snippet?: string; source?: string | { name?: string }; stories?: SerpNews[] };

const sourceName = (s: SerpNews["source"]): string => (typeof s === "string" ? s : s?.name) ?? "unknown source";

export function parseNews(json: unknown): NewsItem[] {
  const body = json as { error?: string; news_results?: SerpNews[] };
  if (body.error) {
    if (/hasn't returned any results|no results/i.test(body.error)) return [];
    throw new Error(`News search failed: ${body.error}`);
  }
  const items: NewsItem[] = [];
  const add = (entry: SerpNews) => {
    if (!entry.title || !entry.link) return;
    items.push({ title: entry.title, source: sourceName(entry.source), publishedAt: parseNewsDate(entry.date), link: entry.link, snippet: entry.snippet });
  };
  for (const entry of body.news_results ?? []) {
    // A result can be a cluster of stories about the same event; each story is a headline of its own.
    if (entry.stories?.length) entry.stories.forEach(add); else add(entry);
  }
  const seen = new Set<string>();
  const unique = items.filter((item) => { const key = item.link; if (seen.has(key)) return false; seen.add(key); return true; });
  // Newest first; items without a readable time go last.
  return unique.sort((a, b) => (b.publishedAt ?? "").localeCompare(a.publishedAt ?? ""));
}

export interface NewsProvider {
  search(query: NewsQuery): Promise<NewsItem[]>;
}

export class SerpApiNews implements NewsProvider {
  private apiKey: string;
  private fetchFn: FetchFn;

  constructor(apiKey: string, fetchFn: FetchFn = (url) => fetch(url)) {
    this.apiKey = apiKey;
    this.fetchFn = fetchFn;
  }

  async search(query: NewsQuery): Promise<NewsItem[]> {
    const response = await this.fetchFn(serpApiNewsURL(query, this.apiKey));
    const json = await response.json().catch(() => ({ error: `unreadable answer (HTTP ${response.status})` }));
    if (!response.ok && !(json as { error?: string }).error) throw new Error(`News search failed (HTTP ${response.status}).`);
    return parseNews(json);
  }
}

function age(publishedAt: string | null, nowMs: number): string {
  if (!publishedAt) return "time unknown";
  const hours = Math.round((nowMs - Date.parse(publishedAt)) / 3_600_000);
  const when = publishedAt.slice(0, 16).replace("T", " ") + " UTC";
  return hours < 1 ? `${when}, under an hour ago` : hours < 48 ? `${when}, ${hours} h ago` : `${when}, ${Math.round(hours / 24)} days ago`;
}

export function describeNews(query: NewsQuery, items: NewsItem[], nowMs: number, limit = 8): string {
  if (items.length === 0) return `No news found for "${query.query}".`;
  const lines = [`Latest news for "${query.query}" (newest first):`];
  items.slice(0, limit).forEach((item, i) => {
    lines.push(`${i + 1}. [${age(item.publishedAt, nowMs)}] ${item.source}: ${item.title}${item.snippet ? ` | ${item.snippet.slice(0, 140)}` : ""} | ${item.link}`);
  });
  lines.push("Write the answer only from these headlines. Say which outlet reported each point and when; where outlets differ or a claim is disputed, say so; never add facts that are not listed. Keep it short and end with the links.");
  return lines.join("\n");
}
