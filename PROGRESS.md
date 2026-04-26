# BentoDeck — Progress & Handoff

> **For a fresh Claude Code session:** read this first, then `CLAUDE.md`,
> then `ARCHITECTURE.md`. You'll be productive in ≤ 5 minutes.
>
> **Last updated:** 2026-04-26 18:21 (commit `d97bdc2`).
> **Submission deadline:** 2026-04-26 20:00 EST.

---

## Where we are right now

**The build is feature-complete and demo-ready.** All three test surfaces
green, all three Apple ambient surfaces working, all nine Opus 4.7 call
sites firing. The remaining work is **recording + submitting**, not
coding.

```
Backend (TypeScript)    13 test files     116 Vitest cases   ~1.4s
iOS (Swift)              8 test files      81 XCTest cases   ~14s
End-to-end (bash)        1 script          16 assertions     ~14s
                                          ─────────────────
                          22 test files    213 assertions
```

**Run all three before any demo recording:**

```bash
# Server tests
(cd server && npm test)
# iOS tests
(cd ios && xcodebuild test -project BentoDeck.xcodeproj -scheme BentoDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO)
# End-to-end (also exercises the full demo backend pipeline)
./scripts/e2e-smoke.sh
```

Last known-good run: 213/213 green, 2026-04-26.

---

## What's shipped

### Server (TypeScript MCP + HTTP backend)

- **Two-process model.** `npm start` runs the always-on backend (HTTP +
  poller + SQLite + AI). `npm run mcp` runs the thin stdio MCP client
  Claude Desktop spawns; it proxies tool calls over HTTP to the backend.
  Production-shaped: one backend can serve many short-lived MCP clients.
- **17 MCP tools** (see `server/src/mcp/server.ts`):
  - `ping`
  - **Dashboards:** `create_dashboard`, `list_dashboards`, `delete_dashboard`,
    `set_dashboard_theme`
  - **Data sources:** `add_data_source`, `discover_data_source` (Tier-2
    docs-driven), `list_data_sources`
  - **Widgets:** `add_widget`, `list_widgets`, `create_widget_from_intent`
    (the hero AI tool)
  - **Read-side (Claude pulls data BACK):** `get_widget_state`,
    `list_investigations`, `get_investigation`
  - **Themes:** `list_themes`, `apply_theme_preset`, `generate_theme`
- **22 HTTP routes** (see `server/src/http/server.ts` + `routes.ts`).
- **Polling scheduler** (5 s tick, per-source `pollIntervalSec`,
  JMESPath transforms applied per widget).
- **Cost-control gate** — value-unchanged short-circuit + anomaly state
  carry-forward + z-score pre-filter (≥2.5σ) + 20-call/widget/day cap.
  Idle drift pays $0; a real spike fires once and persists. See
  `server/src/scheduler/anomaly-gate.ts` and `ARCHITECTURE.md`.
- **Two-tier AI:**
  - Tier 1: Messages-API anomaly call → ≤140-char wrist-buzz sentence.
  - Tier 2: **Claude Managed Agents** session → multi-paragraph runbook,
    streamed back to SQLite incrementally. See `server/src/ai/investigator.ts`.
  - Agent + Environment IDs cached in SQLite `kv` table so the per-poll
    setup cost is paid once, not every anomaly.
- **Six preset themes + AI theme generator.** `generate_theme(prompt)` →
  Opus 4.7 emits a complete theme JSON with WCAG-AA contrast checks.
- **Demo mock API** at `/demo/*` — Stripe / Supabase / PostHog stand-ins
  with internal drift + spike control. **`/demo/control/seed-investigation`**
  produces a polished 3.5-second-streaming pre-canned report so the demo
  recording doesn't depend on real Managed Agents latency.

### iOS (SwiftUI + WidgetKit + ActivityKit)

- **Three Apple ambient surfaces** — all theme-driven end-to-end:
  - **Home Screen widgets** (small + medium 2×2 bento grid) with
    sparklines and trend badges.
  - **Lock Screen widgets** (accessoryCircular + accessoryRectangular +
    accessoryInline).
  - **Live Activities** (Lock Screen banner + Dynamic Island
    compact / minimal / expanded). Started by the app via
    `Activity.request(...)` so no APNs needed.
- **In-app dashboard view** with anomaly banner that's a tap-target into
  the investigation deep-dive.
- **InvestigationDetailView** polls `/investigations/:id` every 1.5 s
  while running; renders Markdown sections (`##`, `-`, paragraphs) with
  AttributedString for inline `**bold**` and `` `code` ``.
- **Background App Refresh** + **Local Notifications** replace APNs.
- **Deep links** via `bentodeck://` URL scheme so widget taps and Live
  Activity taps land on the right view.

### Tooling / Docs

- `README.md` — public vision, competitor analysis, USP, scope, quickstart.
- `CLAUDE.md` — operational rules every Claude Code session loads.
- `ARCHITECTURE.md` — system diagrams, data flow, cost gate, two-tier AI.
- `SUBMISSION.md` — hackathon judging-criteria mapping with build log.
- `scripts/e2e-smoke.sh` — 16-assertion pre-demo gate. **Run this before
  recording.**

---

## Demo flow (locked)

```
1. Conversation → live widget          Claude Desktop → MCP → JMESPath
                                       inferred by Opus → widget on phone
2. Live AI theming                     "Make it retro trading floor" →
                                       theme JSON streams to all surfaces
3. Tier-2 endpoint discovery           "Also monitor my Linear backlog" →
                                       Opus reads the docs + verifies
4. Anomaly fires                       npm run demo:spike → cost gate
                                       passes → wrist buzz + Live Activity
5. Tap-to-investigate                  Banner tap → streaming Markdown
                                       report from Managed Agents session
6. Loop back to chat                   "What does the investigation say?"
                                       → Claude calls get_investigation →
                                       summarises in chat
```

For the recording, **use `npm run demo:seed-investigation` instead of
waiting for real Managed Agents** — same UI flow, deterministic ~3.5 s
streaming.

---

## Operational gotchas (don't get burned)

- **The `.env` file holds `ANTHROPIC_API_KEY`.** Already in
  `.gitignore`. NEVER commit it.
- **Free personal Apple team only.** No APNs push, no TestFlight, no
  Watch complications on real device. Workarounds in place; don't try to
  use APNs.
- **`npm start` and Claude Desktop are not exclusive.** Claude Desktop
  spawns `npm run mcp` (stdio); the backend is `npm start` (HTTP). They
  don't compete for port 3737. Run both.
- **xcodegen** is required to regenerate the Xcode project after editing
  `ios/project.yml` or adding new Swift files. After every iOS source
  addition: `cd ios && xcodegen generate`.
- **Snapshot ordering** — SQLite `datetime('now')` has 1-second
  resolution. All snapshot queries tiebreak on `id DESC` after `ts DESC`.
  Don't remove the tiebreaker; it'll silently break carry-forward.
- **Cost gate** — see `ARCHITECTURE.md`. The four layers in the anomaly
  detection path are not optional. Removing any of them risks runaway
  Opus spend at scale.
- **Live Activities** require `NSSupportsLiveActivities=true` in the app
  target's Info.plist (already set via `project.yml`).
- **App Group** is `group.com.intuitostudio.bentodeck` and must be
  enabled on BOTH the app target and the widget extension target. If the
  widget shows "—" or "BENTO" instead of real values, this is the first
  thing to check.

---

## Explicitly out of scope (don't propose unprompted)

- Apple Watch native code (would need a watchOS target + extra signing
  chain).
- Drag-and-drop dashboard canvas / visual builder UI.
- Template marketplace.
- Android / Wear OS.
- WebSocket / SSE real-time data sources.
- Action widgets (v1 is read-only).
- AppIntentConfiguration for per-widget dashboard selection (considered,
  scope cost > demo value).
- Anything requiring a paid Apple Developer Program account.
- Removing or weakening the four-layer anomaly cost gate.

---

## Known small issues (low priority, none blocking the demo)

- **`DashboardSummary.CodingKeys`** is a no-op enum with a misleading
  comment about a "tolerant decoder path" that doesn't exist. If the
  server ever returned snake_case, fields would silently be `nil`. Worth
  cleaning up post-hackathon.
- **`Color(hex:)`** doesn't accept 3-digit shorthand (`#FFF`). By
  design, but a future Opus theme could emit it. Easy to add.
- **`SnapshotValue.displayString` for `.object`** is latent (no server
  path produces an object value yet). Tested but unexercised.
- **`demo/mock-api.ts`** has module-scope mutable state + ambient
  `setInterval`. Brittle for future deterministic tests; fine for now.
- The widget's medium-size tile previously rendered the timestamp
  twice — actually it doesn't, but the small widget shows the timestamp
  while the medium tiles don't (intentional, space).

---

## What the next session should do

In priority order. Each item is a self-contained ~30 min – 2 h chunk.

### Pre-submission (highest priority — submission is at 8 PM EST)

1. **Push to a public GitHub repo.** Update the `<TBD>` URL in
   `SUBMISSION.md`. The repo is currently local-only at
   `/Users/morris/Documents/Git/bentodeck`. Create a `bentodeck` repo
   under whatever GitHub user/org you want, push, paste the URL.
2. **Rehearse the demo end-to-end** in real time — full 6-step flow
   above. Note any rough transitions.
3. **Record the 3-minute demo video.** Loom or YouTube unlisted.
   Update the demo URL in `SUBMISSION.md`.
4. **Submit** via the Cerebral Valley platform by 8 PM EST.

### Post-submission (any time)

- Investigation history view (right now you can only see the latest
  investigation per widget).
- Apple Watch app — feasible on free personal team; mostly signing-chain
  legwork.
- AppIntentConfiguration for per-widget dashboard selection.
- General SwiftUI polish (animations, transitions, empty-state copy
  with a copy-MCP-config-snippet button).
- iOS test for `Sparkline` rendering.

---

## Repo map

```
bentodeck/
├── README.md                Public vision + quickstart
├── CLAUDE.md                Operational rules (loaded every session)
├── ARCHITECTURE.md          System diagrams + data flow + cost gate spec
├── SUBMISSION.md            Hackathon writeup with judging-criteria map
├── PROGRESS.md              This file
├── LICENSE                  MIT
├── .gitignore
├── scripts/
│   └── e2e-smoke.sh         16-assertion pre-demo gate
├── server/                  TypeScript backend
│   ├── package.json
│   ├── src/
│   │   ├── index.ts                  Backend entry (npm start)
│   │   ├── mcp-entry.ts              MCP thin client entry (npm run mcp)
│   │   ├── mcp/server.ts             17 MCP tools (HTTP-proxying)
│   │   ├── http/
│   │   │   ├── server.ts             Read-side HTTP routes
│   │   │   └── routes.ts             Write-side + AI routes
│   │   ├── ai/
│   │   │   ├── client.ts             Anthropic SDK singleton
│   │   │   ├── setup.ts              JMESPath + widget-type planner
│   │   │   ├── anomaly.ts            Wrist-buzz one-sentence explainer
│   │   │   ├── theme.ts              Vibe → theme JSON
│   │   │   ├── discoverer.ts         Tier-2 docs → REST spec
│   │   │   └── investigator.ts       Claude Managed Agents incident loop
│   │   ├── scheduler/
│   │   │   ├── poller.ts             Poll loop with carry-forward
│   │   │   └── anomaly-gate.ts       z-score + daily cap
│   │   ├── db/
│   │   │   ├── schema.ts             SQLite schema + initDb
│   │   │   └── repo.ts               Typed repository
│   │   ├── sources/fetch.ts          REST fetcher + sample capping
│   │   ├── themes/presets.ts         Six preset themes
│   │   ├── demo/mock-api.ts          /demo/* + investigation seeder
│   │   └── types/schemas.ts          Zod domain schemas
│   ├── scripts/
│   │   ├── seed-demo.ts              Pre-canned dashboard for demos
│   │   └── smoke-poller.ts           GitHub-API live smoke
│   └── *.test.ts                     13 Vitest files alongside subjects
└── ios/                     Xcode project (xcodegen-generated)
    ├── project.yml                   Source of truth for the Xcode proj
    ├── BentoDeck.entitlements        App Group
    ├── BentoDeckWidget.entitlements  App Group
    ├── Sources/
    │   ├── App/                      Main app (SwiftUI)
    │   │   ├── BentoDeckApp.swift            @main + BG task registry
    │   │   ├── RootView.swift                NavigationStack + deep links
    │   │   ├── DashboardListView.swift
    │   │   ├── DashboardDetailView.swift     Anomaly banner + tap-to-investigate
    │   │   ├── WidgetCardView.swift          6 widget render branches
    │   │   ├── InvestigationDetailView.swift Streaming Markdown report
    │   │   ├── RefreshManager.swift          BGAppRefresh + Local Notifs
    │   │   └── LiveActivityManager.swift     Reconcile Live Activities
    │   ├── Widget/                   WidgetKit extension
    │   │   ├── BentoDeckWidgetBundle.swift
    │   │   ├── Provider.swift                Timeline provider
    │   │   ├── HomeWidget.swift              small + medium
    │   │   ├── LockWidget.swift              circular + rectangular + inline
    │   │   └── AnomalyLiveActivity.swift     Lock + Dynamic Island
    │   └── Shared/                   Models used by both targets
    │       ├── Config.swift                  baseURL + BentoDeckLink
    │       ├── Theme.swift                   Color(hex:) + Theme Codable
    │       ├── Dashboard.swift               SnapshotResponse + JSONValue
    │       ├── APIClient.swift               URLSession + Investigation
    │       ├── SharedStore.swift             App Group UserDefaults
    │       ├── Sparkline.swift               Pure-SwiftUI sparkline
    │       └── AnomalyAttributes.swift       ActivityAttributes
    └── Tests/                        8 XCTest files
```

---

## Recent decisions (last ~24h, with reasoning)

| Decision | Reasoning |
|---|---|
| Split MCP from backend (commit `9ec6aad`) | User pushed back on Claude Desktop running the backend. Production-shaped split: backend always-on, MCP per-conversation. |
| Add 4-layer cost gate (`a511247`) | User's SaaS-cost concern. Naive design ≈ \$150/user/mo; gated design ≈ \$0.15/user/mo (1000× reduction). |
| Remove warmup gate (`e72d368`) | Found bug: warmup blocked persistent-spike anomalies forever. Statistical filter + value-unchanged short-circuit handle the original concern. |
| Carry anomaly state forward (`e9b85fb`) | iOS banner was vanishing on every poll because new snapshot rows defaulted to `anomaly=false`. Carry it forward when the value is unchanged. |
| Demo investigation seeder (`a703f7a`) | Real Managed Agents takes 30-60 s; demo recording needs deterministic timing. Same UI path, faked 3.5 s streaming. |
| Read-side MCP tools (`dde9e07`) | Closes the loop: Claude can pull data BACK after pushing config. Enables "what does the investigation say?" demo beat. |
| Snapshot ordering tiebreaker (`dde9e07`) | SQLite `datetime('now')` 1-second resolution → multiple writes in same second → undefined order. Tiebreak on `id DESC`. |

---

## How a fresh session should react to common asks

| User says | Do this |
|---|---|
| "Continue" / "keep going" | Re-read this doc, pick from "What the next session should do", do the highest-priority item not yet done, commit cleanly. |
| "Run the demo" | `./scripts/e2e-smoke.sh` confirms backend pipeline. For the iOS-side demo, the user has to drive (Xcode + simulator). |
| "What's broken?" | Nothing major. See "Known small issues". Run E2E + both test suites to verify. |
| "Add Apple Watch" | Only if the user *explicitly* asks. Not on the must-have list, real signing-chain risk. |
| "Make it cheaper" | The cost gate is already designed for SaaS scale. If the user wants more, suggest Haiku 4.5 as anomaly default + Opus on escalation, BYOK option for power users. |
| "Why is it broken on my phone?" | First check the LAN IP in `Sources/Shared/Config.swift`. Default is `localhost`, only works on simulator. Physical iPhone needs the Mac's LAN IP. |
| "Refactor X for production" | Look at it skeptically — most things ARE production-shaped already. Don't churn for the sake of churn. |
