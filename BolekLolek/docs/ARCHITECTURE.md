# Bolek & Lolek — Architecture (prototype)

Status: draft v0.1 · Scope: prototype · Names are working titles and may change.

## 1. Product in one paragraph

One iPhone app with two buttons. **Lolek** is a private assistant that runs
entirely on the phone with a small open model and never talks to any server
of ours. **Bolek** is a full personal agent (in the style of Meta Muse) that
runs Kimi K3 in confidential-computing enclaves hosted in the EU and can act on
the web and in connected services. The app is international, Polish and English
from day one, and must work especially well in Poland.

## 2. Decisions so far

| Area | Decision |
|---|---|
| Devices | iPhone 15 Pro and newer only (8 GB RAM). Minimum iOS 18. SwiftUI. |
| App shape | One app, two buttons: Lolek / Bolek. Separate memories by default. |
| Lolek model | **Qwen3.5 4B** (chosen by the tool-calling scorecard; Bielik v3 4.5B was evaluated and dropped, see LOLEK_RUNTIME.md). A new model is a `ModelProfile` + prompt style. |
| Lolek privacy | Talks to no server of ours. Only network traffic: one-off model download, and — if the user connects it — direct phone ↔ mail-provider traffic (e.g. Gmail). No analytics on content. |
| Bolek model | **Kimi K3** on Phala GPU TEE (attested). |
| Bolek hosting | EU only. |
| Languages | Polish + English from the ground up. UI follows the phone language; agent replies in the language the user writes in. |
| Voice | Not in v1. Future update. |
| Pricing | Lolek: one-off purchase (price TBD). Bolek: subscription. |
| Bolek v1 scope | (1) email & calendar, (2) reminders / recurring tasks / monitoring, (3) web research & form filling, (4) Polish services with real APIs. Shopping/checkout, phone calls, BLIK: later. |

## 3. Where the code lives

`BolekLolek/` at the root of this repository, fully independent of
`PetConsumptionTracker/` (no shared files, separate Xcode project). It can be
moved into its own repository later with `git subtree split --prefix=BolekLolek`.

```
BolekLolek/
  docs/                 architecture, privacy model, services catalog, evals
  ios/                  iOS app (XcodeGen project.yml → .xcodeproj on a Mac)
    App/                SwiftUI app, Lolek/Bolek switch, shared chat UI
    Packages/
      AgentCore/        shared harness: loop, tools, memory, approvals
      LolekRuntime/     on-device inference (llama.cpp), model registry
      BolekClient/      API client for the Bolek backend
      Localization/     String Catalogs, PL/EN formatting helpers
  backend/              Bolek orchestrator (EU), connectors, scheduler
  evals/                PL/EN task suites for model selection
```

The Xcode project is generated from `project.yml` with XcodeGen, which keeps the
project file out of merge conflicts and lets the project be defined on any
machine. Building and running still needs a Mac with Xcode.

## 4. System overview

```
                         ┌────────────────── iPhone ──────────────────┐
                         │  SwiftUI app  [ Lolek ]  [ Bolek ]          │
                         │        │                    │               │
                         │   AgentCore (shared loop, tool registry,    │
                         │   memory format, approvals UI)              │
                         │        │                    │               │
                         │  LolekRuntime          BolekClient ─────────┼──► EU backend
                         │  llama.cpp + Qwen3.5   (HTTPS, per-user     │    (orchestrator)
                         │  Qwen GGUF, on-device  keys)                │        │
                         │        │                                    │        ▼
                         │  On-device tools: notes, reminders,         │   Phala GPU TEE
                         │  EventKit, Contacts, email (direct to       │   Kimi K3 (attested)
                         │  Gmail/IMAP), local memory                  │        │
                         └────────┼────────────────────────────────────┘        ▼
                                  └──► mail provider only            connectors, browser
                                       (if user connects)            sandbox, scheduler
```

## 5. Shared harness — `AgentCore`

One agent loop, two "brains". Switching Lolek ↔ Bolek changes the model provider
and the set of tools that are allowed, not the app.

- **`ModelProvider` protocol**: `generate(messages, tools, constraints) -> stream`.
  Implementations: `LlamaCppProvider` (Lolek), `BolekRemoteProvider` (Bolek runs
  its loop server-side; the phone renders events and approvals).
- **`ModelProfile`** per model: chat template, tool-call format, stop tokens,
  context budget, sampling defaults, system prompts (PL and EN). Swapping the
  on-device model is a profile change plus a prompt style.
- **`Tool` protocol** with metadata: `name`, JSON schema, `tier` (`lolek`,
  `bolek`, `both`), `risk` (`read`, `write`, `send`, `spend`), localized
  descriptions.
- **Approvals**: any tool with risk `send`/`spend`/`write-external` pauses and
  asks: *allow once / always allow / deny*. Same UI for both modes.
- **Memory**: markdown-style records (identity, user facts, memories) stored
  per mode. "Forget X" deletes matching records. Lolek and Bolek memories are
  separate; sharing is an explicit, off-by-default setting.
- **Activity log**: every tool call and approval is recorded locally and
  visible to the user.

## 6. Lolek — on-device

### Runtime
- **llama.cpp** (Metal) packaged as an XCFramework inside `LolekRuntime`.
  Runs both model families from GGUF files.
- Request the `com.apple.developer.kernel.increased-memory-limit` entitlement.
- Context budget: 8K tokens to start (memory and speed on the A17 Pro).
- **Grammar-constrained decoding** (GBNF/JSON schema) for tool calls, so a 4B
  model can't emit malformed calls.

### Model
**Qwen3.5-4B** (`Qwen3.5-4B-Q4_K_M.gguf`, 2.74 GB): strong tool calling, hybrid architecture,
201 languages. It scored 12/12 on the PL/EN tool-calling scorecard on every run. **Bielik v3 4.5B**
(Polish-first, Apache-2.0) was evaluated and dropped: 9-10/12 with invented tool calls and
over-claimed abilities. Details and the swap procedure are in LOLEK_RUNTIME.md.

The model is quantized to about Q4_K_M (~2.7 GB), downloaded once inside the app
from a pinned URL and checked against a SHA-256 hash. No other network call is
involved.

The choice was made by the eval suite (§10), not by preference.

### Lolek tools (v1)
Kept small on purpose, to about 8 tools, with at most 1–2 planning steps.

| Tool | Implementation |
|---|---|
| Notes & lists | Local SQLite / SwiftData |
| Reminders (time + location) | `UNUserNotificationCenter`, geofencing via Core Location, all local |
| Calendar read/add | EventKit |
| Contacts lookup | Contacts framework |
| Email: list / read / summarize / draft / send | Direct from phone: Gmail API via OAuth (`ASWebAuthenticationSession`) or IMAP/SMTP (WP, Onet, Interia, iCloud…). `send` requires approval. |
| Summarize / translate PL↔EN shared text | Share extension → local model |
| Local memory search | On-device |
| Hand off to Bolek | Saves a task to an outbox; sends only if the user taps "Send to Bolek" |

### Lolek privacy rules (enforced, not just promised)
- No analytics or crash reporting that includes content. Crash reporting is
  off by default.
- Network use is limited to: the model download host, and mail hosts the user
  connected. Enforced by a single networking layer with an allowlist, plus
  tests.
- Data on disk uses iOS Data Protection (`complete`). Tokens live in the
  Keychain.
- Gmail note: production access to Gmail's restricted scopes needs Google's
  security assessment (CASA). The prototype runs in testing mode (≤100 test
  users) or uses IMAP with an app password.

## 7. Bolek — cloud agent in the EU

### Components
| Component | Prototype choice |
|---|---|
| Model | Kimi K3 via Phala's OpenAI-compatible API on GPU TEE; the client verifies attestation |
| Orchestrator | TypeScript/Node service: agent loop, tool router, approvals, event stream to the app |
| Scheduler | Job queue (e.g. BullMQ on Redis) for reminders, recurring tasks, monitors |
| Browser sandbox | Per-user Playwright browser in an isolated container |
| Connectors | MCP servers plus first-party adapters (see §8) |
| Credentials | Vault, never placed in model context; values injected by code at use time |
| Auth & billing | Sign in with Apple; StoreKit 2 subscription |
| Push | APNs for approvals and monitor alerts |
| Region | EU only (exact provider and region TBD; confirm Phala EU capacity) |

### Privacy path
- **Prototype:** orchestrator runs on EU infrastructure and inference runs in
  Phala's TEE. Per-user encryption keys for stored data.
- **Target:** move the orchestrator and browser into confidential VMs (Phala
  CVM, Intel TDX / AMD SEV-SNP) so that no Bolek component sees plaintext
  outside attested hardware.
- Tamper-evident activity log that the user can read.

## 8. Services catalog (Bolek v1 = groups 1–4)

Legend: **API** = official or documented API · **Browser** = done through the
agent's browser sandbox · **Later** = not in v1.

### 1. Email & calendar
| Service | Approach |
|---|---|
| Gmail, Google Calendar | API (OAuth) |
| Outlook / Microsoft 365 | API (Microsoft Graph) |
| WP Poczta, Onet Poczta, Interia, o2, iCloud Mail | IMAP/SMTP |
| iCloud / other calendars | CalDAV |

### 2. Reminders, recurring tasks, monitoring
Built into the orchestrator. Data sources with open public APIs:
| Source | Approach |
|---|---|
| Weather & warnings (IMGW) | API (public data) |
| Air quality (GIOŚ) | API (public) |
| Exchange rates (NBP) | API (public) |
| Price / availability monitoring on any page | Browser |

### 3. Web research & form filling
Research, comparison, and filling out forms through the browser sandbox, with
approval before any submit. Government portals (mObywatel, ePUAP, e-Urząd
Skarbowy): information and help only in v1, no automated submission.

### 4. Polish services
| Service | Approach | v1 use |
|---|---|---|
| InPost | API (ShipX) / public tracking | Track parcels, notify on status |
| Poczta Polska, DPD, DHL, GLS, Orlen Paczka | Tracking APIs where available, otherwise Browser | Parcel tracking |
| Allegro | API (REST, user OAuth) | Watch items, purchase history, messages |
| OLX, Vinted | Browser | Search and watch listings |
| Booksy | Browser | Find and book appointments (approval required) |
| ZnanyLekarz, Medicover, LUX MED | Browser | Find appointment slots |
| PKP Intercity, Koleo, Jakdojade | Browser / open GTFS data | Connections, prices |
| Banks (read-only) | Open-banking aggregator: Kontomatik (PL), Salt Edge (strong CEE coverage), Tink or Enable Banking | Balances, transactions, subscription finder |
| Pyszne.pl, Glovo, Wolt, Frisco, Ceneo | Browser | Later (shopping) |
| BLIK, payments | — | Later |

### International connectors
Notion, Slack, Google Drive, Microsoft OneDrive, Dropbox and GitHub through MCP
where a well-maintained server exists.

## 9. Bilingual from the ground up
- Xcode **String Catalogs** (`.xcstrings`) with `pl` and `en` from the first
  commit. No hard-coded UI strings, enforced by a lint check.
- Polish plurals (one / few / many) handled by String Catalog plural variants.
- Dates, times, numbers and currency (zł / PLN) use `FormatStyle` with the
  user's locale.
- System prompts and tool descriptions exist in PL and EN. The agent replies in
  the language of the user's message and handles mixed PL/EN text.
- Polish test fixtures everywhere: names with diacritics, Polish addresses and
  postcodes, IBAN/NRB, PESEL masked in logs.

## 10. Model evaluation (Lolek and Bolek)
A fixed task suite in **Polish and English**, run against every candidate:
- Tool selection and argument accuracy (e.g. "przypomnij mi jutro o 9 o
  wizycie u dentysty")
- Email summarize and draft quality, with grammar checked by native reviewers
- Following instructions across 1–3 steps
- Answering in the right language, and diacritics/inflection quality
- On-device speed (tokens/s), time to first token, peak memory and heat on an
  iPhone 15 Pro

Output: a scorecard per model. Lolek's default model is the winner.

## 11. Build order
1. **Skeleton**: XcodeGen project, app shell, Lolek/Bolek switch, String
   Catalogs PL/EN, `AgentCore` protocols.
2. **Lolek runtime**: llama.cpp integration, model download and verification,
   streaming chat, `ModelProfile` for Qwen. **Done**, see LOLEK_RUNTIME.md.
3. **Lolek tools**: notes, reminders, EventKit, contacts, constrained tool
   calls, approvals UI.
4. **Evals v1**: PL/EN suite and model scorecard. Pick Lolek's default.
5. **Lolek email**: Gmail OAuth and IMAP, summarize and draft, send with
   approval.
6. **Bolek backend**: orchestrator, Phala Kimi K3 provider, event stream,
   Sign in with Apple.
7. **Bolek services**: email & calendar, scheduler and monitors, browser
   sandbox, Polish services (InPost, Allegro first).
8. **Bolek privacy hardening**: confidential VMs, attestation checks in the
   app, per-user keys.

## 12. Open questions and risks
- Qwen3.5 4B's tool calling is strong on the 12-case scorecard, but Polish prose quality at 4B is
  unscored and nothing has been measured on an iPhone yet (speed, heat, memory with a 2.7 GB model).
- Phala capacity and region in the EU must be confirmed.
- Gmail restricted-scope verification (CASA) is needed before a public launch.
- Many Polish services have no public API. Browser automation is fragile and
  some sites block bots, so the agent should identify itself and prefer
  official APIs.
- Open-banking aggregators need a commercial contract and, for some, a
  licensed partner.
- Kimi K3's license has conditions at scale (MaaS revenue over $20M a year;
  branding over 100M MAU). Branding is ignored for now, as agreed.

## Bolek backend (flights and price watches)

`backend/` is a small zero-dependency Node server. The agent loop stays on the phone; the server only runs Bolek's remote tools
(`search_flights`, `watch_flight_price`, `list_flight_watches`, `stop_flight_watch`) and stores alerts when a watched fare drops.

- **Phone side:** `AgentCore/Tools/RemoteTools.swift` (`BackendClient`, `RemoteTool`). On every foreground the app fetches `/v1/tools`, registers them for Bolek only
  (tier `.bolek`; watch tools are `writeExternal`, so the user is asked first), then pulls `/v1/alerts` and shows each as a Bolek message.
- **No server or no key:** Bolek simply has no flight tools, or the tool says plainly that flight search is not set up. Nothing crashes, nothing is invented.
- **Config (developer builds):** launch once with `BOLEK_BACKEND_URL` and `BOLEK_BACKEND_TOKEN`; the token goes to the Keychain.
  The Info.plist allows local-network HTTP only (`NSAllowsLocalNetworking`); a server outside the home network needs HTTPS (Tailscale or a reverse proxy).
- **Privacy:** route and dates reach SerpApi/Google. Lolek never uses the backend.
- **Not verified:** a live SerpApi call (no key yet), alerts on a real phone, push notifications (alerts show when the app opens).
