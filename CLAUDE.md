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

- **Backend:** TypeScript / Node. MCP SDK for the server. Hono or Express for HTTP the iOS app polls. SQLite (via `better-sqlite3`) as the initial data store.
- **AI:** Opus 4.7 (`claude-opus-4-7`) via Anthropic TypeScript SDK. With prompt caching.
- **Transform runtime:** JMESPath as default (pure-TS + pure-Swift implementations exist). Sandboxed JS deferred post-hackathon.
- **iOS:** SwiftUI + WidgetKit, Xcode 16, free personal team signing (7-day re-sign is acceptable for the demo window).
- **Data source (v1):** REST polling with API-key auth only. WebSocket/SSE deferred.

## Apple development constraints (real operational limits)

- User has Mac + Xcode 16+ + physical iPhone + paired Apple Watch.
- User does **NOT** have a paid Apple Developer Program account — no APNs push, no TestFlight, no complications on a real device.
- User has **not shipped Swift/SwiftUI before.** Claude writes the Swift; user compiles and runs.
- Workaround for missing APNs: **Local Notifications** fired by Background App Refresh when the app detects an anomaly flag from the backend. Demo reads identical.

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
- Anything requiring a paid Apple Developer account.

## How we work

- **Demo-driven development.** Every scope decision is pressure-tested against "does this improve the 3-minute demo video?" If not, defer.
- **Opus 4.7 is the #1 scoring criterion (25%).** Push decisions onto Opus 4.7 rather than hard-coding rules — transforms, widget suggestions, anomaly detection, theme generation, anomaly explanations are all live Opus 4.7 calls.
- **Clean, semantic commits.** Small commits are fine. Mystery "wip" commits are not.
- **No half-finished code.** If a file exists in the repo, it compiles and runs.
- **Don't over-engineer.** This is a hackathon prototype, not a production SaaS. No microservices, no Kubernetes, no premature abstractions. SQLite + a single Node process is fine.

## Demo scenario (locked)

Indie SaaS founder persona. Sources: Stripe test mode (MRR), Supabase (signups), mock PostHog (errors).

1. User types in Claude Desktop: *"Show me Stripe MRR, today's signups, error count on my Home Screen."*
2. Claude calls BentoDeck's MCP tools. Backend hits sample API responses, Opus 4.7 generates JMESPath transforms live.
3. iPhone Home Screen: widget appears with live numbers.
4. Errors spike in test data. Local Notification fires with an Opus 4.7 plain-English explanation.
5. User (via Claude Desktop): *"Mute for an hour."* → done.

## Key files

- `README.md` — public vision, mission, competitors, USP. Read first.
- `CLAUDE.md` — this file. Operational rules only.
- `server/` (to be created) — TypeScript MCP + HTTP backend.
- `ios/` (to be created) — Xcode project for the iOS app + widget extension.
