# CLAUDE.md

Operational context for Claude when working in this repo. For the full vision, mission, problem statement, competitor analysis, and USP, read [README.md](./README.md) first.

## What this project is (one line)

Native iOS app + TypeScript MCP server that bridges Claude Desktop's MCP-connected intelligence to Apple's ambient glance surfaces (Home Screen widgets, Lock Screen, later Apple Watch).

## Hackathon constraints (non-negotiable)

- **Deadline:** Sunday, 2026-04-26 at 8:00 PM EST. Every decision is measured against this.
- **Open-source from commit one.** MIT license. Repo URL will appear in the submission video.
- **New code only** — nothing predates the hackathon start (2026-04-21).
- **Solo builder**, Claude Code is the pair-programmer.

## Locked stack choices

- **Backend:** TypeScript / Node. MCP SDK + Hono HTTP. SQLite (`better-sqlite3`).
- **AI:** Opus 4.7 (`claude-opus-4-7`) via Anthropic TypeScript SDK with prompt caching, plus **Claude Managed Agents** (beta header `managed-agents-2026-04-01`) for the long-running incident investigator.
- **Transform runtime:** JMESPath (pure-TS + pure-Swift implementations exist). Sandboxed JS deferred.
- **iOS:** SwiftUI + WidgetKit + ActivityKit (Live Activities), free personal team signing.
- **Data source (v1):** REST polling. Two registration paths:
  1. Direct: caller supplies URL + auth (`add_data_source` MCP tool).
  2. Tier-2 discovery: caller supplies the platform's docs URL + intent + API key, Opus 4.7 reads the docs and emits + verifies the spec (`discover_data_source` MCP tool).
- **Process model (production-shaped):**
  - `npm start` — backend only (HTTP + poller + SQLite + AI). Always-on.
  - `npm run mcp` — thin stdio MCP client Claude Desktop spawns; proxies tool calls over HTTP to the backend at `BENTODECK_BASE_URL`.

## Cost-control architecture (don't accidentally remove)

The poll loop's anomaly-detection AI calls are gated by, in order:

1. Value-unchanged short-circuit (no model call when value is identical to prior tick).
2. Anomaly state carry-forward (when value is unchanged AND the previous snapshot was anomalous, propagate the flag + explanation forward — keeps the iOS banner visible across persistent spikes).
3. Statistical pre-filter: z-score over a 24-point rolling window; only call AI when `|z| ≥ 2.5`. See `server/src/scheduler/anomaly-gate.ts`.
4. Per-widget daily cap: max 20 AI calls per widget per 24h.

Outcome: idle drift pays $0 in AI cost; a real spike fires once and persists via carry-forward. Projected SaaS cost ≈ $0.15/user/month, vs. ~$150/user/month if you call AI on every poll.

A separate **Managed Agents investigator** is kicked off only when an anomaly fires; it writes a multi-paragraph runbook in a sandboxed container, streamed back and persisted incrementally (`server/src/ai/investigator.ts`). Agent + Environment IDs are cached in the SQLite `kv` table so we don't re-create them per investigation.

## Apple development constraints (real operational limits)

- User has Mac + Xcode 16+ + physical iPhone + paired Apple Watch.
- User does **NOT** have a paid Apple Developer Program account — no APNs push, no TestFlight, no Apple Watch complications on a real device.
- User had **not shipped Swift/SwiftUI before** the hackathon. Claude writes the Swift; user compiles and runs.
- Workarounds enabled by free personal team signing:
  - **Local Notifications** triggered by Background App Refresh (replaces APNs push for anomaly alerts).
  - **Live Activities** via `Activity.request(...)` (no APNs needed) — Lock Screen banner + Dynamic Island.
- Apple Watch app is the only ambient surface still deferred — would need to add a watchOS target and the additional signing chain risk wasn't justified for the demo window.

## Scope discipline

**In-scope for v1 (see README for the full list).** Anything not on that list is deferred. When a new idea appears:

1. State the idea.
2. State the hackathon judging criterion it serves.
3. State what it displaces from the current plan if added.
4. Only after those three, consider adding it.

**Explicitly out of scope — do not propose unprompted:**
- Apple Watch native code (deferred post-hackathon).
- Drag-and-drop canvas or visual builder UI.
- Template marketplace.
- Android / Wear OS.
- WebSocket real-time sources.
- Action widgets (v1 is read-only).
- Anything requiring a paid Apple Developer account (APNs, TestFlight, on-device complications).
- Removing or weakening the four-layer anomaly cost gate (see "Cost-control architecture" above).

## How we work

- **Demo-driven development.** Every scope decision is pressure-tested against "does this improve the 3-minute demo video?" If not, defer.
- **Opus 4.7 is the #1 scoring criterion (25%).** Push decisions onto Opus 4.7 rather than hard-coding rules — transforms, widget suggestions, anomaly detection, theme generation, anomaly explanations are all live Opus 4.7 calls.
- **Clean, semantic commits.** Small commits are fine. Mystery "wip" commits are not.
- **No half-finished code.** If a file exists in the repo, it compiles and runs.
- **Don't over-engineer.** This is a hackathon prototype, not a production SaaS. No microservices, no Kubernetes, no premature abstractions. SQLite + a single Node process is fine.

## Demo scenario (locked)

Indie SaaS founder persona. Mock sources at `/demo/*` on the backend stand in for Stripe (MRR), Supabase (signups), and PostHog (errors).

1. **Conversation → live widget.** User types in Claude Desktop: *"Show me Stripe MRR, today's signups, errors on my Home Screen."* Claude calls `create_dashboard` → `add_data_source` (×3) → `create_widget_from_intent` (×3); Opus 4.7 generates JMESPath transforms + picks widget types live.
2. **Theming.** *"Make it retro trading floor."* Opus emits a complete WCAG-checked theme JSON; the dashboard re-skins everywhere.
3. **Tier-2 discovery (optional beat).** *"Also monitor my Linear backlog."* Opus reads the docs, emits + verifies the endpoint.
4. **Anomaly.** Presenter calls `npm run demo:spike` → cost gate passes (z = ∞) → Opus writes the wrist-buzz sentence → Local Notification + Live Activity (Lock Screen banner + Dynamic Island).
5. **Tap-to-investigate.** Tap the Live Activity → app → tap anomaly banner → InvestigationDetailView shows the streaming Markdown report from the Managed Agents session.
6. **Loop back to chat.** *"What does the investigation say?"* Claude calls `get_investigation` → summarises and discusses mitigations.

For a demo recording where waiting 30-60s for real Managed Agents would hurt pacing, `npm run demo:seed-investigation` seeds a polished pre-canned report that streams in over ~3.5s — same UI path, deterministic timing.

## Key files

- `README.md` — public vision, mission, competitors, USP. Read first.
- `CLAUDE.md` — this file. Operational rules.
- `SUBMISSION.md` — hackathon writeup with judging-criteria mapping.
- `scripts/e2e-smoke.sh` — 16-assertion end-to-end check; run before any demo recording.
- `server/` — TypeScript MCP thin client + HTTP backend + AI + poller + SQLite. 116 Vitest cases.
- `ios/` — xcodegen-generated Xcode project; SwiftUI app + WidgetKit extension. 81 XCTest cases.
