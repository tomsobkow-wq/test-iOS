/** A page the user can open themselves. Only https links to real sites are ever passed on to the app. */
export interface SourceLink {
  title: string;
  site: string;
  url: string;
}

export function sourceLink(title: string, site: string, url: string): SourceLink | undefined {
  let parsed: URL;
  try { parsed = new URL(url); } catch { return undefined; }
  if (parsed.protocol !== "https:" || parsed.username || parsed.password || !parsed.hostname.includes(".")) return undefined;
  return { title: title.replace(/\s+/g, " ").trim().slice(0, 120), site: site.trim().slice(0, 60) || parsed.hostname.replace(/^www\./, ""), url: parsed.toString().slice(0, 2000) };
}
