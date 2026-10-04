# Lolek runtime (build step 2): what was built and what was measured

Package: `ios/Packages/LolekRuntime`. Everything below was verified against the real files, not recalled.

## Models

| | Qwen3.5 4B (default) | Bielik v3 4.5B Instruct |
|---|---|---|
| File | `unsloth/Qwen3.5-4B-GGUF` · `Qwen3.5-4B-Q4_K_M.gguf` | `second-state/Bielik-4.5B-v3.0-Instruct-GGUF` · `…-Q4_K_M.gguf` |
| Size | 2,740,937,888 B | 2,878,886,912 B |
| SHA-256 | `00fe7986…ef11a4` | `39fb78db…6763e1` |
| Architecture | `qwen35`, **hybrid** (cannot rewind its memory) | `llama` (plain attention) |
| Template | ChatML, thinking off by default, tools in system prompt | plain ChatML with `<s>`, **no tool support** |
| Tool calls | XML: `<tool_call><function=name><parameter=k>v</parameter></function></tool_call>` | none native; we ask for JSON in `<tool_call>` tags |

Both SHA-256 values were checked against the downloaded files. The official SpeakLeash repo only has fp16 and Q8_0
(too big for an 8 GB phone); the Q4_K_M above is the second-state build, and gaianet's upload has the same hash.

The placeholder profile assumed Qwen3.5 used Hermes JSON tool calls. **It does not.** `Tools/gen_golden.py` renders the
chat templates embedded in the GGUF files with Jinja, and `GoldenPromptTests` require our Swift renderer to match
byte for byte (tools, tool loops, parallel calls, multi-turn).

## Tool-calling scorecard (12 PL/EN requests, strict: any unrequested tool call fails)

Run: `LOLEK_MODEL_DIR=~/Developer/lolek-models swift test --filter testToolCallingScorecard`

- **Qwen3.5 4B: 12/12** on every run. Picks the right tool, correct arguments, answers in the user's language.
- **Bielik v3 4.5B: 9–10/12**, varies between runs. Knows which tool, but often skips the `<tool_call>` tags (we accept bare
  JSON for known tool names) and invents calls for greetings and jokes (`add_calendar_event`, `text_contact`,
  `set_spending_tracking`). It also over-claims abilities in plain chat and copies prompt timestamps into replies.

`ModelCatalog.lolekDefault` is therefore Qwen3.5 4B. Switching is a one-line change there. Polish prose quality has not
been scored yet (needs native reviewers, ARCHITECTURE §10).

## Speed: why there are checkpoints

Qwen3.5 is hybrid, so llama.cpp cannot drop just the tail of its memory: with the usual "keep the common prefix"
trick it re-read **0 of 707** tokens every step. The engine saves the model's memory state at the end of the fixed header
(instructions and tools) and at the end of each prompt body, and restores the best match (what llama.cpp's own server does).
Measured on a Mac: follow-up prefill **2.98 s → 0.15 s**. Each checkpoint is about 74 MB at 680 tokens; at most 3 are kept.
Bielik does not need this (its prefix reuse works directly).

To keep the cache valid, the system prompt must not change between turns, so the current date is not in it. User messages
carry a `[Monday 2026-10-05 09:41]` stamp instead, and `ModelRequest.now` carries the clock to remote providers.
On app start (and after the download) `AgentSession.warmUp()` reads the header, so the first message is quick.

Numbers above are from a Mac (about 23 tokens/s generation). **Nothing has been measured on an iPhone yet.** Expect it to be
slower; the first thing to do with a device is run the scorecard and check heat and memory (2.7 GB model plus checkpoints).

## llama.cpp binary

The official release zip (`llama-b11388-xcframework.zip`) has device and macOS slices but **no iOS Simulator slice**, so the
app cannot build for the simulator with it. `Tools/build-llama-xcframework.sh` builds device, simulator and macOS from the
pinned tag into `Vendor/llama.xcframework` (git-ignored, about 10 minutes, needs `brew install cmake`).
`Package.swift` uses it when present and falls back to the official zip otherwise (device and macOS only).
Whoever sets up a Mac for simulator builds needs to run the script once.

## Download

`ModelDownloader`: resumable (HTTP Range, `.part` file), checks free space first, verifies SHA-256 and size before the file
is allowed to run, deletes corrupt downloads, excluded from iCloud backup. It uses a normal URLSession, so the download
pauses if the app is suspended and resumes from the `.part` file next time; a background URLSession is a later improvement.

## Not done yet

- Grammar-constrained decoding (ARCHITECTURE §6) was not needed to reach 12/12 on Qwen; revisit if wider evals show bad calls.
- Persisting checkpoints to disk (would make even the first message after a cold start quick).
- Tool routing (sending only relevant tools) to shrink the 1.7k-token prompt.
- Real-device measurements, thermal behaviour, and the `increased-memory-limit` capability on a signed build.
- A background download session.
