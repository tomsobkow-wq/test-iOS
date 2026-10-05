// General web search (Google results, localised) and a careful page reader, for things the specific tools do not cover:
// used items on classified sites, local businesses, how-to questions. Search goes through SerpApi like the other tools.
import { lookup as dnsLookup } from "node:dns";
import { lookup } from "node:dns/promises";
import { request } from "node:https";
import { isIP, isIPv6 } from "node:net";
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
  lines.push("These are search results, not checked listings, and snippets can be out of date (a listing may have sold). For a question about finding something for sale, call read_page on the two or three most relevant results BEFORE answering (do not just offer to), then answer from what the live pages show; if a page shows no listing say so instead of quoting the snippet. Report only what the titles, snippets and pages say (for example year, price, kilometres, place), name the site for each, and say that details and availability must be confirmed on the site. Do not print web addresses.");
  return lines.join("\n");
}

// MARK: Page reader

/** An IPv6 address as a 128-bit number, or null when it is not valid. Handles "::", an embedded dotted IPv4 and a zone id. */
export function ipv6ToBigInt(address: string): bigint | null {
  let a = address.split("%")[0].toLowerCase();
  if (a.startsWith("[") && a.endsWith("]")) a = a.slice(1, -1);
  if (!isIPv6(a)) return null;
  const dotted = a.match(/(\d+\.\d+\.\d+\.\d+)$/);
  if (dotted) {
    const p = dotted[1].split(".").map(Number);
    a = `${a.slice(0, -dotted[1].length)}${((p[0] << 8) | p[1]).toString(16)}:${((p[2] << 8) | p[3]).toString(16)}`;
  }
  const halves = a.split("::");
  if (halves.length > 2) return null;
  const head = halves[0] ? halves[0].split(":") : [];
  const tail = halves.length === 2 && halves[1] ? halves[1].split(":") : [];
  const fill = halves.length === 2 ? 8 - head.length - tail.length : 0;
  const groups = [...head, ...Array<string>(Math.max(0, fill)).fill("0"), ...tail];
  if (groups.length !== 8) return null;
  let value = 0n;
  for (const g of groups) value = (value << 16n) | BigInt(parseInt(g || "0", 16));
  return value;
}

function privateIPv4(a: number, b: number, c: number): boolean {
  return a === 0 || a === 10 || a === 127 || a >= 224 || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) || (a === 169 && b === 254) ||
    (a === 100 && b >= 64 && b <= 127) || (a === 192 && b === 0 && (c === 0 || c === 2)) || (a === 198 && (b === 18 || b === 19)) ||
    (a === 198 && b === 51 && c === 100) || (a === 203 && b === 0 && c === 113);
}

/**
 * Private, loopback, link-local, reserved and unparseable addresses must never be fetched on the user's behalf.
 * IPv6 is compared as a number, and any address that carries an IPv4 inside it (mapped, NAT64, 6to4) is judged by that IPv4.
 */
export function isPrivateAddress(address: string): boolean {
  if (isIP(address) === 4) {
    const [a, b, c] = address.split(".").map(Number);
    return privateIPv4(a, b, c);
  }
  const v = ipv6ToBigInt(address);
  if (v === null) return true;
  const inside = (prefix: bigint, bits: bigint) => (v >> (128n - bits)) === (prefix >> (128n - bits));
  const v4 = (n: bigint): boolean => privateIPv4(Number((n >> 24n) & 255n), Number((n >> 16n) & 255n), Number((n >> 8n) & 255n));
  if (v === 0n || v === 1n) return true;                                   // :: and ::1
  if (inside(0xffffn << 32n, 96n)) return v4(v & 0xffffffffn);             // ::ffff:a.b.c.d (IPv4-mapped)
  if (v >> 32n === 0n) return true;                                        // ::a.b.c.d (IPv4-compatible, deprecated)
  if (inside(0x64n << 112n | 0xff9bn << 96n, 96n)) return v4(v & 0xffffffffn); // 64:ff9b::/96 (NAT64)
  if (inside(0x2002n << 112n, 16n)) return v4((v >> 80n) & 0xffffffffn);   // 2002::/16 (6to4)
  if (inside(0x2001n << 112n, 32n)) return true;                           // 2001::/32 Teredo
  if (inside(0x2001n << 112n | 0x0db8n << 96n, 32n)) return true;          // documentation range
  if (inside(0xfc00n << 112n, 7n)) return true;                            // unique local
  if (inside(0xfe80n << 112n, 10n) || inside(0xfec0n << 112n, 10n)) return true; // link-local, site-local
  if (inside(0xffn << 120n, 8n)) return true;                              // multicast
  return false;
}

/**
 * A DNS lookup for the page fetch that does the check and the answer in one step: the address the connection uses is the one that
 * was just checked, so a host that answers "public" to a separate check and "private" to the connection cannot get through.
 */
export function makeSafeLookup(resolver: (host: string) => Promise<string[]> = async (h) => (await lookup(h, { all: true })).map((r) => r.address)) {
  return (hostname: string, options: { all?: boolean }, callback: (err: Error | null, address?: unknown, family?: number) => void): void => {
    resolver(hostname).then((addresses) => {
      if (addresses.length === 0 || addresses.some(isPrivateAddress)) return callback(new Error("address not allowed"));
      const wrap = (a: string) => ({ address: a, family: isIP(a) });
      if (options.all) return callback(null, addresses.map(wrap));
      callback(null, addresses[0], isIP(addresses[0]));
    }, (error) => callback(error instanceof Error ? error : new Error("lookup failed")));
  };
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

const safeLookup = makeSafeLookup();

const defaultPageFetch: PageFetch = (url) => new Promise((resolve, reject) => {
  const parsed = new URL(url);
  // An address typed as a number is never looked up, so it is judged here, before any connection.
  const literal = parsed.hostname.replace(/^\[|\]$/g, "");
  if (isIP(literal) !== 0 && isPrivateAddress(literal)) return reject(new Error("address not allowed"));
  const req = request(parsed, {
    method: "GET", timeout: 8000, lookup: safeLookup as never,
    headers: { "user-agent": "Mozilla/5.0 (compatible; BolekAssistant/1.0)", accept: "text/html,text/plain" },
  }, (res) => {
    const chunks: Buffer[] = [];
    let size = 0;
    res.on("data", (chunk: Buffer) => {
      size += chunk.length;
      chunks.push(chunk);
      if (size > 500_000) res.destroy();   // enough to read the top of any page
    });
    const finish = () => resolve({ status: res.statusCode ?? 0, location: res.headers.location ?? null, type: String(res.headers["content-type"] ?? ""), body: Buffer.concat(chunks).toString("utf8") });
    res.on("end", finish);
    res.on("close", finish);
    res.on("error", reject);
  });
  req.on("timeout", () => req.destroy(new Error("timeout")));
  req.on("error", reject);
  req.end();
});

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
