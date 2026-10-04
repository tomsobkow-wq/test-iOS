# Bolek backend

Server-side tools for Bolek: **real flight prices**, **price watching**, and **alerts**. The agent loop stays on the phone (it needs the phone's own tools);
this server holds what needs a key or a clock. No dependencies: Node 24+ runs the TypeScript, SQLite and tests directly.

```
BOLEK_API_TOKEN=<random, 16+ chars> SERPAPI_KEY=<key> node src/server.ts     # http://127.0.0.1:8787
node --test                                                                   # 24+ tests, no network, no key needed
```

| Setting | Default | |
|---|---|---|
| `BOLEK_API_TOKEN` | required | the app sends it as `Authorization: Bearer ...` |
| `SERPAPI_KEY` | none | without it flight tools say so plainly; everything else works |
| `HOST` / `PORT` | `127.0.0.1` / `8787` | set `HOST=0.0.0.0` on purpose to reach it from a phone |
| `SERPAPI_MONTHLY_LIMIT` | 200 | searches per month the server allows itself (SerpApi free plan: 250) |
| `MAX_WATCHES` / `CHECK_EVERY_HOURS` | 3 / 12 | a watch checked twice a day costs about 60 searches a month |

API: `GET /healthz` · `GET /v1/tools` · `POST /v1/tools/call {name, arguments}` · `GET /v1/alerts?since=<id>` · `POST /v1/alerts/seen {upTo}`.

Tools: `search_flights`, `watch_flight_price` (asks the user first), `list_flight_watches`, `stop_flight_watch (asks first)`.
Flights need exact dates; city names are mapped to airport codes. Prices come from Google Flights through SerpApi and are not a booking.

Privacy: the route and dates of a search go to SerpApi and Google. Nothing else about the user does. Request bodies are never logged.
Not done: push notifications (alerts are stored and the app fetches them; APNs needs a signed build and an Apple key), accounts (one user), HTTPS (put it behind Tailscale or a reverse proxy).
