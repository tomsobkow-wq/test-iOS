// General web search (Google results, localised) and a careful page reader, for things the specific tools do not cover:
// used items on classified sites, local businesses, how-to questions. Search goes through SerpApi like the other tools.
import { lookup } from "node:dns/promises";
import type { FetchFn } from "./flights.ts";

export interface WebQuery {
  query: string;
  country: string;
  language: string;
  /** A place name that narrows results, e.g. "Perth, Western Australia, Australia". */
  location?: string;
}

export interface WebResult {
  title: string;
  source: string;
  snippet: string;
  link: string;
}

export function serpApiWebURL(q: WebQuery, apiKey: string): string {
  const params = new URLSearchParams({ engine: "google", q: q.query, gl: q.country, hl: q.language, num: "10", api_key: apiKey });
  if (q.location) params.set("location", q.location);
  return `https://serpapi.com/search.json?${params}`;
}

type SerpOrganic = { title?: string; link?: string; snippet?: string; source?: string; displayed_link?: string };

export function parseWeb(json: unknown): WebResult[] {
  const body = json as { error?: string; organic_results?: SerpOrganic[] };
  if (body.error) {
    if (/hasn't returned any results|no results/i.test(body.error)) return [];
    throw new Error(`Web search failed: ${body.error}`);
  }
  const results: WebResult[] = [];
  for (const item of body.organic_results ?? []) {
    if (!item.title || !item.link || !/^https?:\/\//i.test(item.link)) continue;
    results.push({ title: item.title, source: item.source ?? item.displayed_link?.split(" ")[0] ?? new URL(item.link).hostname, snippet: (item.snippet ?? "").replace(/\s+/g, " ").trim(), link: item.link });
  }
  return results;
}

export interface WebProvider {
  search(query: WebQuery): Promise<WebResult[]>;
}

export class SerpApiWeb implements WebProvider {
  private apiKey: string;
  private fetchFn: FetchFn;

  constructor(apiKey: string, fetchFn: FetchFn = (url) => fetch(url)) {
    this.apiKey = apiKey;
    this.fetchFn = fetchFn;
  }

  async search(query: WebQuery): Promise<WebResult[]> {
    const response = await this.fetchFn(serpApiWebURL(query, this.apiKey));
    const json = await response.json().catch(() => ({ error: `unreadable answer (HTTP ${response.status})` }));
    if (!response.ok && !(json as { error?: string }).error) throw new Error(`Web search failed (HTTP ${response.status}).`);
    return parseWeb(json);
  }
}

export function describeWeb(query: WebQuery, results: WebResult[], limit = 8): string {
  const where = query.location ? ` near ${query.location}` : "";
  if (results.length === 0) return `No web results for "${query.query}"${where}.`;
  const lines = [`Web results for "${query.query}"${where}:`];
  results.slice(0, limit).forEach((r, i) => lines.push(`${i + 1}. ${r.source}: ${r.title}${r.snippet ? ` | ${r.snippet.slice(0, 220)}` : ""}`));
  lines.push("These are search results, not checked listings, and snippets can be out of date (a listing may have sold). Open the most promising results with read_page to see the live page, and if a page shows no listing say so instead of quoting the snippet. Report only what the titles, snippets and pages say (for example year, price, kilometres, place), name the site for each, and say that details and availability must be confirmed on the site. Do not print web addresses. To read more of one result, call read_page with its number.");
  return lines.join("\n");
}

// MARK: Page reader

/** Private, loopback and link-local addresses must never be fetched on the user's behalf. */
export function isPrivateAddress(address: string): boolean {
  if (address.includes(":")) {
    const a = address.toLowerCase();
    return a === "::1" || a === "::" || a.startsWith("fc") || a.startsWith("fd") || a.startsWith("fe8") || a.startsWith("fe9") || a.startsWith("fea") || a.startsWith("feb") || a.startsWith("::ffff:127.") || a.startsWith("::ffff:10.") || a.startsWith("::ffff:192.168.");
  }
  const parts = address.split(".").map(Number);
  if (parts.length !== 4 || parts.some((n) => !Number.isInteger(n) || n < 0 || n > 255)) return true;
  const [a, b] = parts;
  return a === 10 || a === 127 || a === 0 || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) || (a === 169 && b === 254) || (a === 100 && b >= 64 && b <= 127) || a >= 224;
}

export type Resolver = (host: string) => Promise<string[]>;
const defaultResolver: Resolver = async (host) => (await lookup(host, { all: true })).map((r) => r.address);

export function readableText(html: string, limit = 3500): string {
  const text = html
    .replace(/<(script|style|noscript|svg|head|nav|footer|form|iframe)[\s\S]*?<\/\1>/gi, " ")
    .replace(/<!--[\s\S]*?-->/g, " ")
    .replace(/<\/(p|div|li|tr|h[1-6]|section|article|br)>|<br\s*\/?>/gi, "\n")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'")
    .split("\n").map((line) => line.replace(/[ \t]+/g, " ").trim()).filter(Boolean).join("\n");
  return text.length > limit ? `${text.slice(0, limit)}\n[…cut]` : text;
}

const BLOCKED = /px-captcha|captcha|access denied|just a moment|enable javascript|are you a robot|unusual traffic|cf-chl|verify you are human/i;

export type PageFetch = (url: string) => Promise<{ status: number; location?: string | null; type: string; body: string }>;

const defaultPageFetch: PageFetch = async (url) => {
  const response = await fetch(url, { redirect: "manual", signal: AbortSignal.timeout(8000), headers: { "user-agent": "Mozilla/5.0 (compatible; BolekAssistant/1.0)", accept: "text/html,text/plain" } });
  const reader = response.body?.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (reader) {
    const { done, value } = await reader.read();
    if (done || !value) break;
    size += value.length;
    chunks.push(value);
    if (size > 500_000) { await reader.cancel(); break; }  // enough to read the top of any page
  }
  return { status: response.status, location: response.headers.get("location"), type: response.headers.get("content-type") ?? "", body: Buffer.concat(chunks).toString("utf8") };
};

export interface PageReadResult { ok: boolean; text: string }

/**
 * Reads one page for the model. https only, public hosts only (every redirect is checked too), a few seconds, a few hundred KB.
 * Sites that block automated reading are reported as such, never worked around.
 */
export async function readPage(url: string, deps: { resolve?: Resolver; fetchPage?: PageFetch } = {}): Promise<PageReadResult> {
  const resolve = deps.resolve ?? defaultResolver;
  const fetchPage = deps.fetchPage ?? defaultPageFetch;
  let current = url;
  for (let hop = 0; hop < 4; hop++) {
    let parsed: URL;
    try { parsed = new URL(current); } catch { return { ok: false, text: "That address is not valid." }; }
    if (parsed.protocol !== "https:") return { ok: false, text: "Only secure (https) pages can be read." };
    if (parsed.username || parsed.password) return { ok: false, text: "That address is not allowed." };
    let addresses: string[];
    try { addresses = await resolve(parsed.hostname); } catch { return { ok: false, text: "That site could not be found." }; }
    if (addresses.length === 0 || addresses.some(isPrivateAddress)) return { ok: false, text: "That address is not allowed." };
    let page: Awaited<ReturnType<PageFetch>>;
    try { page = await fetchPage(current); } catch { return { ok: false, text: "The page did not load in time." }; }
    if (page.status >= 300 && page.status < 400 && page.location) { current = new URL(page.location, current).toString(); continue; }
    if (page.status === 403 || page.status === 429 || page.status === 503 || BLOCKED.test(page.body.slice(0, 4000))) {
      return { ok: false, text: "This site blocks automated reading (it needs a person with a browser). Use the search snippets and tell the user to open the site themselves." };
    }
    if (page.status >= 400) return { ok: false, text: `The page answered with an error (${page.status}).` };
    if (!/text\/html|text\/plain|application\/xhtml/i.test(page.type)) return { ok: false, text: "That is not a readable web page." };
    const text = readableText(page.body);
    return text.length < 80 ? { ok: false, text: "The page has no readable text (it may need a browser to show its content)." } : { ok: true, text };
  }
  return { ok: false, text: "Too many redirects." };
}
