# Lolek runtime (build step 2): what was built and what was measured

Package: `ios/Packages/LolekRuntime`. Everything below was verified against the real files, not recalled.

## Model

**Qwen3.5 4B**, `unsloth/Qwen3.5-4B-GGUF` · `Qwen3.5-4B-Q4_K_M.gguf`, 2,740,937,888 bytes,
SHA-256 `00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4` (checked against the downloaded file).
Architecture `qwen35`, hybrid (cannot rewind its memory). Chat template: ChatML, thinking off by default, tools in the
system prompt, calls as XML: `<tool_call><function=name><parameter=k>v</parameter></function></tool_call>`, results as
`<tool_response>` in a user turn.

The placeholder profile assumed Hermes JSON tool calls. **It was wrong.** `Tools/gen_golden.py` renders the chat template
embedded in the GGUF file with Jinja, and `GoldenPromptTests` require our Swift renderer to match byte for byte (tools,
tool loops, parallel calls, multi-turn).

### Why not Bielik (evaluated and dropped)

Bielik v3 4.5B Instruct (Q4_K_M from second-state; the official SpeakLeash repo only has fp16 and Q8_0, too big for 8 GB)
has a plain ChatML template with no tool support. On the same scorecard, with strict scoring (any unrequested tool call fails):

| | Qwen3.5 4B | Bielik v3 4.5B |
|---|---|---|
| Tool-calling scorecard (12 PL/EN requests) | **12/12**, every run | 9-10/12, varies between runs |
| Failure mode | none seen | invents calls for greetings and jokes (`add_calendar_event`, `text_contact`, `set_spending_tracking`); skips `<tool_call>` tags; over-claims abilities; copies prompt timestamps into replies |

Its Polish prose was fluent, but not enough to offset acting on things the user never asked for. The code for it was removed;
git history before the "remove Bielik" commit has the plain-ChatML renderer if a future comparison needs it.

## Scorecard (12 PL/EN requests, strict)

Run: `LOLEK_MODEL_DIR=~/Developer/lolek-models swift test --filter testToolCallingScorecard`. Covers weather, alarm, timer,
reminder, text, call, expense, spending summary, calendar, a greeting and a joke. A lookup first (`find_contact`) is allowed;
any other unrequested tool call fails the case. Polish prose quality has not been scored (needs native reviewers, ARCHITECTURE §10).

## Speed: why there are checkpoints

Qwen3.5 is hybrid, so llama.cpp cannot drop just the tail of its memory: with the usual "keep the common prefix"
trick it re-read **0 of 707** tokens every step. The engine saves the model's memory state at the end of the fixed header
(instructions and tools) and at the end of each prompt body, and restores the best match (what llama.cpp's own server does).
Measured on a Mac: follow-up prefill **2.98 s → 0.15 s**. Each checkpoint is about 74 MB at 680 tokens; at most 3 are kept.

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
