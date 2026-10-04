# Bolek & Lolek (prototype)

One iPhone app, two assistants:

- **Lolek**: private, runs fully on the phone (Qwen3.5 4B), never talks to our servers.
- **Bolek**: full personal agent on Kimi K3 in EU-hosted confidential enclaves.

Polish and English from day one. Fully separate from `PetConsumptionTracker/`:
own folder, own Xcode project (`BolekLolek.xcodeproj`), own bundle ID
(`com.boleklolek.app`).

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Run it (Mac)

```sh
brew install xcodegen          # once
cd BolekLolek/ios
xcodegen generate              # creates BolekLolek.xcodeproj (git-ignored)
open BolekLolek.xcodeproj
```

In Xcode, pick your team under Signing & Capabilities, then run on an
iPhone 15 Pro (or its simulator). Re-run `xcodegen generate` after pulling
changes that add or remove files.

## Tests

```sh
cd BolekLolek/ios/Packages/AgentCore
swift test
```

## What works now (build step 1)

- Lolek / Bolek buttons, each with its own chat, tools and memory.
- Shared agent loop (`AgentCore`): tool tiers per mode, step limits,
  approvals (allow once / always allow / deny), activity log.
- Polish and English UI from a String Catalog, including Polish plural forms.
  The agent replies in the language you write in.
- A scripted demo model stands in for the real ones. Try `note: buy milk`,
  `notatka: kupić mleko`, or `send: hello` (shows the approval sheet).
