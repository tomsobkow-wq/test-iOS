import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import { timingSafeEqual } from "node:crypto";
import { loadConfig, type Config } from "./config.ts";
import { openDb, type Db } from "./db.ts";
import { SerpApiFlights, type FlightProvider } from "./flights.ts";
import { Quota } from "./quota.ts";
import { startScheduler } from "./scheduler.ts";
import { ToolFailure, tools, type ToolContext } from "./tools.ts";
import { listAlerts, markAlertsSeen } from "./watches.ts";

export interface AppDeps {
  config: Config;
  db: Db;
  quota: Quota;
  provider: FlightProvider | undefined;
  now?: () => number;
}

const USER = "default"; // one person for now; the token will map to a user when there are accounts

function send(res: ServerResponse, status: number, body: unknown): void {
  const text = JSON.stringify(body);
  res.writeHead(status, { "content-type": "application/json; charset=utf-8", "content-length": Buffer.byteLength(text), "cache-control": "no-store" });
  res.end(text);
}

async function readJSON(req: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of req) {
    size += (chunk as Buffer).length;
    if (size > 64 * 1024) throw new Error("body too large");
    chunks.push(chunk as Buffer);
  }
  return chunks.length ? JSON.parse(Buffer.concat(chunks).toString("utf8")) : {};
}

function authorised(req: IncomingMessage, token: string): boolean {
  const header = req.headers.authorization ?? "";
  const given = Buffer.from(header.startsWith("Bearer ") ? header.slice(7) : "");
  const wanted = Buffer.from(token);
  return given.length === wanted.length && timingSafeEqual(given, wanted);
}

export function createApp(deps: AppDeps): Server {
  const now = deps.now ?? Date.now;
  const context = (): ToolContext => ({ db: deps.db, config: deps.config, quota: deps.quota, provider: deps.provider, user: USER, now });

  return createServer(async (req, res) => {
    const url = new URL(req.url ?? "/", "http://localhost");
    try {
      if (req.method === "GET" && url.pathname === "/healthz") return send(res, 200, { ok: true, flights: !!deps.provider });
      if (!url.pathname.startsWith("/v1/")) return send(res, 404, { error: "not found" });
      if (!authorised(req, deps.config.apiToken)) return send(res, 401, { error: "unauthorised" });

      if (req.method === "GET" && url.pathname === "/v1/tools") {
        return send(res, 200, { tools: tools.map(({ name, description, risk, parameters }) => ({ name, description, risk, parameters })) });
      }
      if (req.method === "POST" && url.pathname === "/v1/tools/call") {
        const body = (await readJSON(req)) as { name?: string; arguments?: unknown };
        const tool = tools.find((t) => t.name === body.name);
        if (!tool) return send(res, 404, { ok: false, content: `Unknown tool: ${body.name}` });
        let args: Record<string, unknown> = {};
        try {
          const raw = typeof body.arguments === "string" ? JSON.parse(body.arguments || "{}") : body.arguments ?? {};
          if (typeof raw !== "object" || raw === null || Array.isArray(raw)) throw new Error();
          args = raw as Record<string, unknown>;
        } catch { return send(res, 400, { ok: false, content: "arguments must be a JSON object" }); }
        try {
          return send(res, 200, { ok: true, content: await tool.run(args, context()) });
        } catch (error) {
          // Failures the user or model can fix are returned as text. Anything else is reported without internals.
          return send(res, 200, { ok: false, content: error instanceof ToolFailure || error instanceof Error && /watch|limit/i.test(error.message) ? error.message : "The tool failed on the server. Try again later." });
        }
      }
      if (req.method === "GET" && url.pathname === "/v1/alerts") {
        const since = Number(url.searchParams.get("since") ?? 0) || 0;
        return send(res, 200, { alerts: listAlerts(deps.db, USER, since) });
      }
      if (req.method === "POST" && url.pathname === "/v1/alerts/seen") {
        const body = (await readJSON(req)) as { upTo?: number };
        markAlertsSeen(deps.db, USER, Number(body.upTo ?? 0));
        return send(res, 200, { ok: true });
      }
      return send(res, 404, { error: "not found" });
    } catch {
      return send(res, 400, { error: "bad request" });
    }
  });
}

// Run directly: `BOLEK_API_TOKEN=... SERPAPI_KEY=... node src/server.ts`
if (import.meta.main) {
  const config = loadConfig();
  const db = openDb(config.dbPath);
  const quota = new Quota(db, config.monthlySearchLimit);
  const provider = config.serpApiKey ? new SerpApiFlights(config.serpApiKey) : undefined;
  const server = createApp({ config, db, quota, provider });
  if (provider) startScheduler({ db, provider, quota, onTick: (s) => console.log(`[watches] checked ${s.checked}, alerts ${s.alerts}, failed ${s.failed}, no quota ${s.skippedNoQuota}`) }, config.tickSeconds * 1000);
  server.listen(config.port, config.host, () => {
    console.log(`Bolek backend on http://${config.host}:${config.port}  flights: ${provider ? "SerpApi" : "NOT configured (set SERPAPI_KEY)"}  searches this month: ${quota.used(Date.now())}/${quota.limit}`);
  });
}
