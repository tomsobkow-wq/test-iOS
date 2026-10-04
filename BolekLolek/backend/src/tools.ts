import type { Config } from "./config.ts";
import type { Db } from "./db.ts";
import { resolveAirport } from "./airports.ts";
import { describeResult, money, type FlightProvider, type FlightQuery } from "./flights.ts";
import type { Quota } from "./quota.ts";
import { createWatch, describeWatch, listWatches, searchesPerMonth, stopWatch } from "./watches.ts";

export interface ToolContext {
  db: Db;
  config: Config;
  quota: Quota;
  /** Undefined when no SERPAPI_KEY is set. */
  provider: FlightProvider | undefined;
  user: string;
  now: () => number;
}

export interface ToolDef {
  name: string;
  description: string;
  /** "write" tools change something that lasts (a watch); the app asks the user before running them. */
  risk: "read" | "write";
  parameters: Record<string, unknown>;
  run(args: Record<string, unknown>, ctx: ToolContext): Promise<string>;
}

/** Thrown for problems the model or user can fix. The message is shown to the model as the tool result. */
export class ToolFailure extends Error {}

const str = (args: Record<string, unknown>, key: string): string | undefined => {
  const v = args[key];
  return typeof v === "string" && v.trim() ? v.trim() : undefined;
};
const num = (args: Record<string, unknown>, key: string): number | undefined => {
  const v = args[key];
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string") { const n = Number(v.replace(",", ".").replace(/[^\d.]/g, "")); if (Number.isFinite(n) && n > 0) return n; }
  return undefined;
};
const isDate = (s: string) => /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(Date.parse(s));

function tripFrom(args: Record<string, unknown>, ctx: ToolContext): FlightQuery {
  const originText = str(args, "origin"), destinationText = str(args, "destination"), departDate = str(args, "depart_date");
  if (!originText || !destinationText || !departDate) throw new ToolFailure("origin, destination and depart_date are required. Ask the user for what is missing.");
  const origin = resolveAirport(originText), destination = resolveAirport(destinationText);
  if ("error" in origin) throw new ToolFailure(origin.error);
  if ("error" in destination) throw new ToolFailure(destination.error);
  if (origin.code === destination.code) throw new ToolFailure("Origin and destination are the same airport.");
  if (!isDate(departDate)) throw new ToolFailure("depart_date must be a real date written YYYY-MM-DD. Ask the user for the exact date.");
  const today = new Date(ctx.now()).toISOString().slice(0, 10);
  if (departDate < today) throw new ToolFailure(`depart_date ${departDate} is in the past (today is ${today}).`);
  const returnDate = str(args, "return_date");
  if (returnDate) {
    if (!isDate(returnDate)) throw new ToolFailure("return_date must be a real date written YYYY-MM-DD.");
    if (returnDate < departDate) throw new ToolFailure("return_date is before depart_date.");
  }
  const adults = Math.min(9, Math.max(1, Math.round(num(args, "adults") ?? 1)));
  const currency = (str(args, "currency") ?? "PLN").toUpperCase();
  if (!/^[A-Z]{3}$/.test(currency)) throw new ToolFailure("currency must be a 3-letter code such as PLN or EUR.");
  return { origin: origin.code, destination: destination.code, departDate, returnDate, adults, currency };
}

const tripSchema = {
  origin: { type: "string", description: "City or 3-letter airport code, e.g. Warszawa or WAW" },
  destination: { type: "string", description: "City or 3-letter airport code, e.g. Lizbona or LIS" },
  depart_date: { type: "string", description: "YYYY-MM-DD, an exact date" },
  return_date: { type: "string", description: "YYYY-MM-DD, only for a round trip" },
  adults: { type: "integer" },
  currency: { type: "string", description: "PLN by default" },
};

export const tools: ToolDef[] = [
  {
    name: "search_flights",
    risk: "read",
    description: "Look up real flight prices (Google Flights) for an exact date. Needs origin, destination and depart_date; ask the user for a date if they only said a month.",
    parameters: { type: "object", properties: tripSchema, required: ["origin", "destination", "depart_date"] },
    async run(args, ctx) {
      if (!ctx.provider) throw new ToolFailure("Flight search is not set up on the server yet (no SerpApi key). Tell the user.");
      const query = tripFrom(args, ctx);
      if (!ctx.quota.consume(ctx.now())) throw new ToolFailure(`The monthly flight search allowance (${ctx.quota.limit}) is used up. Tell the user it resets next month.`);
      return describeResult(query, await ctx.provider.search(query));
    },
  },
  {
    name: "watch_flight_price",
    risk: "write",
    description: "Watch a flight price in the background and alert the user when it drops to or below their limit. Needs an exact date and max_price (the alert limit, in the currency).",
    parameters: { type: "object", properties: { ...tripSchema, max_price: { type: "number", description: "Alert when the price is at or below this" }, every_hours: { type: "integer", description: "How often to check, default 12" } }, required: ["origin", "destination", "depart_date", "max_price"] },
    async run(args, ctx) {
      if (!ctx.provider) throw new ToolFailure("Price watching is not set up on the server yet (no SerpApi key). Tell the user.");
      const query = tripFrom(args, ctx);
      const maxPrice = num(args, "max_price");
      if (!maxPrice) throw new ToolFailure("max_price is required: the price at or below which the user wants an alert.");
      const everyHours = Math.min(168, Math.max(6, Math.round(num(args, "every_hours") ?? ctx.config.defaultCheckEveryHours)));
      const watch = createWatch(ctx.db, ctx.user, { ...query, thresholdMinor: Math.round(maxPrice * 100), everyHours }, ctx.now(), ctx.config.maxWatches);
      return `Watching ${describeWatch(watch)}. This uses about ${searchesPerMonth(everyHours)} of the ${ctx.quota.limit} flight searches available each month. The user will get a message here when the price reaches ${money(watch.thresholdMinor, watch.currency)} or less.`;
    },
  },
  {
    name: "list_flight_watches",
    risk: "read",
    description: "List the user's active flight price watches.",
    parameters: { type: "object", properties: {} },
    async run(_args, ctx) {
      const watches = listWatches(ctx.db, ctx.user);
      return watches.length ? `${watches.map(describeWatch).join("\n")}\nSearches used this month: ${ctx.quota.used(ctx.now())} of ${ctx.quota.limit}.` : "No active price watches.";
    },
  },
  {
    name: "stop_flight_watch",
    risk: "write",
    description: "Stop a flight price watch. Pass its id from list_flight_watches.",
    parameters: { type: "object", properties: { id: { type: "string" } }, required: ["id"] },
    async run(args, ctx) {
      const id = str(args, "id");
      if (!id) throw new ToolFailure("id is required. Use list_flight_watches to see the ids.");
      return stopWatch(ctx.db, ctx.user, id) ? `Stopped watch ${id}.` : `There is no active watch with id ${id}.`;
    },
  },
];
