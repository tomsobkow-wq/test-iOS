/** A small in-memory cache with an expiry, so a topic many people ask about costs one search, not many. */
export class TtlCache<T> {
  private items = new Map<string, { value: T; expires: number }>();
  private ttlMs: number;
  private maxEntries: number;

  constructor(ttlMs: number, maxEntries = 500) {
    this.ttlMs = ttlMs;
    this.maxEntries = maxEntries;
  }

  get(key: string, nowMs: number): T | undefined {
    const hit = this.items.get(key);
    if (!hit) return undefined;
    if (hit.expires <= nowMs) { this.items.delete(key); return undefined; }
    return hit.value;
  }

  set(key: string, value: T, nowMs: number): void {
    if (this.items.size >= this.maxEntries) {
      const oldest = this.items.keys().next().value;
      if (oldest !== undefined) this.items.delete(oldest);
    }
    this.items.set(key, { value, expires: nowMs + this.ttlMs });
  }
}
