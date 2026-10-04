// Real fares from Google Flights, through SerpApi (https://serpapi.com/google-flights-api).
// Pure request and response functions are kept apart from the network call so they can be tested with canned JSON.

export interface FlightQuery {
  origin: string;        // IATA code
  destination: string;   // IATA code
  departDate: string;    // YYYY-MM-DD
  returnDate?: string;   // YYYY-MM-DD, makes it a round trip
  adults: number;
  currency: string;      // PLN, EUR, ...
  maxPriceMajor?: number;
}

export interface FlightOffer {
  priceMinor: number;
  currency: string;
  airlines: string[];
  stops: number;
  durationMinutes: number;
  departs: { airport: string; time: string };
  arrives: { airport: string; time: string };
  flightNumbers: string[];
}

export interface FlightResult {
  offers: FlightOffer[];           // cheapest first
  /** Google's own read on whether today's price is low, typical or high. */
  priceLevel?: string;
  typicalRangeMinor?: [number, number];
}

export function serpApiURL(query: FlightQuery, apiKey: string): string {
  const params = new URLSearchParams({
    engine: "google_flights",
    departure_id: query.origin,
    arrival_id: query.destination,
    outbound_date: query.departDate,
    currency: query.currency,
    adults: String(query.adults),
    hl: "en",
    type: query.returnDate ? "1" : "2",
    api_key: apiKey,
  });
  if (query.returnDate) params.set("return_date", query.returnDate);
  if (query.maxPriceMajor) params.set("max_price", String(query.maxPriceMajor));
  return `https://serpapi.com/search?${params}`;
}

type SerpFlight = {
  price?: number;
  total_duration?: number;
  flights?: Array<{
    airline?: string; flight_number?: string; duration?: number;
    departure_airport?: { id?: string; time?: string };
    arrival_airport?: { id?: string; time?: string };
  }>;
};

const toMinor = (major: number) => Math.round(major * 100);

export function parseSerpApi(json: unknown, currency: string): FlightResult {
  const body = json as {
    error?: string; best_flights?: SerpFlight[]; other_flights?: SerpFlight[];
    price_insights?: { price_level?: string; typical_price_range?: number[] };
  };
  if (body.error) {
    // "Google Flights hasn't returned any results for this query." is an answer, not a failure.
    if (/hasn't returned any results|no results/i.test(body.error)) return { offers: [] };
    throw new Error(`Flight search failed: ${body.error}`);
  }
  const offers: FlightOffer[] = [];
  for (const entry of [...(body.best_flights ?? []), ...(body.other_flights ?? [])]) {
    const legs = entry.flights ?? [];
    if (typeof entry.price !== "number" || legs.length === 0) continue;
    const first = legs[0], last = legs[legs.length - 1];
    offers.push({
      priceMinor: toMinor(entry.price),
      currency,
      airlines: [...new Set(legs.map((leg) => leg.airline).filter((a): a is string => !!a))],
      stops: legs.length - 1,
      durationMinutes: entry.total_duration ?? legs.reduce((sum, leg) => sum + (leg.duration ?? 0), 0),
      departs: { airport: first.departure_airport?.id ?? "?", time: first.departure_airport?.time ?? "?" },
      arrives: { airport: last.arrival_airport?.id ?? "?", time: last.arrival_airport?.time ?? "?" },
      flightNumbers: legs.map((leg) => leg.flight_number).filter((n): n is string => !!n),
    });
  }
  offers.sort((a, b) => a.priceMinor - b.priceMinor);
  const range = body.price_insights?.typical_price_range;
  return {
    offers,
    priceLevel: body.price_insights?.price_level,
    typicalRangeMinor: range && range.length === 2 ? [toMinor(range[0]), toMinor(range[1])] : undefined,
  };
}

export interface FlightProvider {
  search(query: FlightQuery): Promise<FlightResult>;
}

export type FetchFn = (url: string) => Promise<{ ok: boolean; status: number; json(): Promise<unknown> }>;

export class SerpApiFlights implements FlightProvider {
  private apiKey: string;
  private fetchFn: FetchFn;

  constructor(apiKey: string, fetchFn: FetchFn = (url) => fetch(url)) {
    this.apiKey = apiKey;
    this.fetchFn = fetchFn;
  }

  async search(query: FlightQuery): Promise<FlightResult> {
    const response = await this.fetchFn(serpApiURL(query, this.apiKey));
    const json = await response.json().catch(() => ({ error: `unreadable answer (HTTP ${response.status})` }));
    if (!response.ok && !(json as { error?: string }).error) throw new Error(`Flight search failed (HTTP ${response.status}).`);
    return parseSerpApi(json, query.currency);
  }
}

// MARK: Text for the model

export function money(minor: number, currency: string): string {
  return `${(minor / 100).toFixed(2)} ${currency}`;
}

export function describeOffer(offer: FlightOffer): string {
  const hours = Math.floor(offer.durationMinutes / 60), minutes = offer.durationMinutes % 60;
  const stops = offer.stops === 0 ? "direct" : `${offer.stops} stop${offer.stops > 1 ? "s" : ""}`;
  return `${money(offer.priceMinor, offer.currency)} | ${offer.airlines.join(" + ")} | ${stops} | ${hours}h${String(minutes).padStart(2, "0")} | `
    + `${offer.departs.airport} ${offer.departs.time} -> ${offer.arrives.airport} ${offer.arrives.time}`;
}

export function describeResult(query: FlightQuery, result: FlightResult, limit = 4): string {
  const trip = `${query.origin} -> ${query.destination}, ${query.departDate}${query.returnDate ? ` (return ${query.returnDate})` : " (one way)"}, ${query.adults} adult${query.adults > 1 ? "s" : ""}`;
  if (result.offers.length === 0) return `${trip}: no flights found for these dates.`;
  const lines = [trip + ". Cheapest first:", ...result.offers.slice(0, limit).map((offer, i) => `${i + 1}. ${describeOffer(offer)}`)];
  if (result.priceLevel) lines.push(`Google says this price is ${result.priceLevel}${result.typicalRangeMinor ? `; typical range ${money(result.typicalRangeMinor[0], query.currency)} to ${money(result.typicalRangeMinor[1], query.currency)}` : ""}.`);
  lines.push("Prices are from Google Flights and can change; they are not a booking.");
  return lines.join("\n");
}
