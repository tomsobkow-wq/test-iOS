# Handoff: start here

For a new Claude Code session picking up this prototype. Read this, then
`ARCHITECTURE.md`.

## Ground rules
- Prototype. Keep it simple.
- **Never touch `PetConsumptionTracker/`** or its Xcode project. It's another
  active project. Everything for this app lives in `BolekLolek/`.
- Work on branch `claude/admiring-galileo-pw37qb`. PR: tomsobkow-wq/test-iOS#6.
- Lolek and Bolek are working names and may change.

## Decisions made with the owner
- One iPhone app, two buttons: **Lolek** (private, on-device) and **Bolek**
  (full agent, cloud). iPhone 15 Pro and newer only, iOS 18+, SwiftUI.
- International app, but must work very well in Poland. Polish + English from
  the ground up. UI follows the phone's language; agent replies in the
  language the user writes in.
- **Lolek**: Qwen3.5-4B (decided after the evals; Bielik was tried and dropped). Originally: designed around Bielik, switchable to Qwen3.5-4B (pick by
  evals). Talks to no server of ours. If the user connects Gmail/IMAP, the
  phone talks to the mail provider directly; that's allowed. One-off price.
- **Bolek**: Kimi K3 on Phala GPU TEE, hosted in the EU. Subscription.
  v1 scope: email & calendar; reminders/recurring tasks/monitoring; web
  research & form filling; Polish services with real APIs. Grab as many
  services as possible over time.
- Voice: later. Branding/licence display: ignore for now.

## Where we are
- Step 1 (skeleton) is written but **has never been compiled**: it was written
  in a Linux cloud session without Xcode.
- First job on the Mac:
  1. `brew install xcodegen` (if missing)
  2. `cd BolekLolek/ios && xcodegen generate`
  3. Build: `xcodebuild -project BolekLolek.xcodeproj -scheme BolekLolek -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build`
     (use any available iPhone 15 Pro-class simulator)
  4. Tests: `cd Packages/AgentCore && swift test`
  5. Fix whatever fails, then commit and push.

## Next
Step 2 in `ARCHITECTURE.md` §11: Lolek runtime. llama.cpp (Metal) on the
phone, model download with SHA-256 verification, streaming, `ModelProfile`s
for Bielik and Qwen verified against the GGUF chat templates.
