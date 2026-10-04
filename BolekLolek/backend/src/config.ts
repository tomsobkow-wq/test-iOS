// Everything the server needs from its environment. Secrets stay here, never on the phone.
export interface Config {
  port: number;
  host: string;
  /** The app presents this as a Bearer token. Required: the server refuses to start without one. */
  apiToken: string;
  serpApiKey: string | undefined;
  dbPath: string;
  /** Searches per month we allow ourselves. SerpApi's free plan is 250; the rest is margin. */
  monthlySearchLimit: number;
  maxWatches: number;
  defaultCheckEveryHours: number;
  /** How often the scheduler looks for watches that are due. */
  tickSeconds: number;
}

export function loadConfig(env: Record<string, string | undefined> = process.env): Config {
  const apiToken = env.BOLEK_API_TOKEN;
  if (!apiToken || apiToken.length < 16) {
    throw new Error("Set BOLEK_API_TOKEN to a random string of at least 16 characters. The app sends it with every request.");
  }
  return {
    port: Number(env.PORT ?? 8787),
    // Loopback by default. Set HOST=0.0.0.0 on purpose to reach it from a phone on your network.
    host: env.HOST ?? "127.0.0.1",
    apiToken,
    serpApiKey: env.SERPAPI_KEY || undefined,
    dbPath: env.DB_PATH ?? "data/bolek.db",
    monthlySearchLimit: Number(env.SERPAPI_MONTHLY_LIMIT ?? 200),
    maxWatches: Number(env.MAX_WATCHES ?? 3),
    defaultCheckEveryHours: Number(env.CHECK_EVERY_HOURS ?? 12),
    tickSeconds: Number(env.TICK_SECONDS ?? 60),
  };
}
