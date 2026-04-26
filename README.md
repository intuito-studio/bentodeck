# BentoDeck

**Claude Desktop's output layer for Apple devices.**

Tell Claude what you want to see. It's on your iPhone Home Screen in 30 seconds. When something's wrong, Claude tells you in plain English on your Lock Screen.

> Built for [Built with Opus 4.7: a Claude Code Hackathon](https://cerebralvalley.ai/e/built-with-4-7-hackathon) — April 21–26, 2026. Open source (MIT). [bentodeck.io](https://bentodeck.io)

---

## Vision

A world where running a system doesn't mean opening a dashboard. You glance at your wrist, your Lock Screen, your Home Screen — and Claude has already put the numbers that matter in front of you. When something's wrong, Claude tells you in plain English before you think to ask. You don't build dashboards anymore; you have a conversation, and the result lives on the surfaces you already look at every day.

## Mission

Make Claude's intelligence **ambient** on Apple devices. BentoDeck is the bridge from Claude Desktop and MCP to the iPhone Home Screen, Lock Screen, Live Activities, and Apple Watch complications — the surfaces Claude itself cannot reach.

## The Problem We Solve

Everyone running a live system — indie SaaS founders, bot traders, AI-app builders, marketers, ops engineers — checks their dashboard 10 to 50 times a day. That dashboard is almost always:

1. **Trapped behind a login in a browser tab on a laptop.** Mobile Safari on a cramped Retool page is nobody's happy place.
2. **Splintered across vendors.** Five different mobile apps for five different systems means no unified glance, just app-switching.
3. **Configured once and abandoned.** When the underlying API changes or the founder's question changes, nobody has 45 minutes to re-wire the dashboard.
4. **Visually sterile.** Dashboards across the category — Numerics, Databox, Plecto, Power BI Mobile, even Grafana — all look like the same cold spreadsheet grid. None of them feel like something you *want* to glance at.

Meanwhile, **Claude Desktop in 2026 already has the intelligence half of this problem solved**. It connects to Stripe, Supabase, PostHog, GitHub, Slack, and countless other systems via MCP. It can investigate, explain, and summarize. But its output is trapped inside the Claude Desktop window — it cannot put a number on your Lock Screen or push an alert to your wrist.

**That last-mile gap — from Claude's conversational intelligence to Apple's ambient glance surfaces — is what BentoDeck closes.**

## Why Now

Three things had to be true, and in April 2026 they all are:

- **MCP is mature enough** that Claude Desktop is a real data-integration platform, not a demo.
- **Opus 4.7 is good enough** to reliably generate transformations, detect anomalies, and explain findings in prose — the three things that make a dashboard feel alive rather than static.
- **Apple's ambient surfaces are developed enough** (WidgetKit, Live Activities, complications, App Intents) that a third-party app can credibly deliver a premium glance experience.

Six months earlier, the models weren't this good. Six months later, someone else ships this.

## Competitive Landscape (honest pros and cons)

**Numerics.io** — the most direct competitor. Apple-native across iPhone, iPad, Mac, tvOS, and Apple Watch; horizontal; supports a bring-your-own REST API custom connector; full widgets and complications. *Pro:* 10+ years of Apple-platform polish; real paying customers. *Con:* Configuration is a form-wizard, not a conversation. SaaS-connector slanted (marketer-friendly), not developer-API first. No AI at setup, no AI at runtime. Per-widget theming ceiling is five fixed tint colors. Everything is static the moment you finish the form.

**Plecto** — enterprise dashboard platform for contact-centers, sales floors, and telecom. *Pro:* Does ship iPhone Home Screen widgets, Lock Screen widgets, and Apple Watch support; has an "AI Formula Assistant" (NL → KPI formula). *Con:* $300/month floor (10-license minimum); deeply scoped to call-center gamification, not solo founders; custom-data API is push-only (you send data *to* Plecto, not pull); theming is a HEX picker gated to the Large tier; no MCP, no Claude Desktop, no NL dashboard creation.

**Retool Mobile** — market leader for internal tooling. *Pro:* Powerful builder, strong auth and data story. *Con:* Mobile is a page-renderer of builder apps — not glanceable, no widgets, no watch, no ambient surface story at all.

**Datadog Mobile** — best-in-class observability on phone. *Pro:* iPhone widgets, Lock Screen widgets, Apple Watch, Live Activities all polished. *Con:* Only works for data already inside Datadog. Enterprise pricing. Closed universe. UI is corporate observability, not delightful.

**Better Stack** — native iOS for uptime monitoring. *Pro:* Clean watch complications, good push UX. *Con:* Vertically scoped to uptime/logs. Can't bring your own API.

**Databox** — Apple Watch KPI app. *Pro:* Early to watch complications, solid widgets. *Con:* SaaS-connector catalog only, no custom APIs, no AI, static layouts.

**Microsoft Power BI Mobile** — the dominant BI tool's mobile app. *Pro:* Deep enterprise reach, Apple Watch support, new iPad Copilot. *Con:* **No iPhone Home Screen widgets at all** (after 5+ years of iOS 14). Mobile layout is author-published; consumers have zero per-user customization. Strictly a published-report viewer, not an ambient glance tool. App Store reviews cite slow loads and memory errors. Not a real competitor for solo founders.

**Grafana IRM** — incident-response paging app. *Pro:* Solid on-call scheduling and alert delivery. *Con:* Wrong category — it's for SREs getting paged at 3am, not founders glancing at MRR. No iOS widgets, no Lock Screen, no Live Activities. Trails even Datadog on mobile ambient surfaces.

**Scriptable / Pushcut** — the DIY baseline. *Pro:* Infinite flexibility, zero cost, a community of power-users hacking personal widgets. *Con:* Write JavaScript per widget. No backend. No watch. No AI. Purely individual use, never organizational.

**Backend Widget: API Dashboard** (App Store) — an existing iOS app that turns any HTTP GET/POST + JSON path into a widget. Effectively "BentoDeck v0 without Claude." *Pro:* Exists, ships real widgets, tiny and focused. *Con:* No MCP, no AI-generated transforms, no natural-language configuration, no Claude Desktop integration, no anomaly explanations. If they ever bolt on Claude, we lose the technical-feature moat and fall back on the Apple-first-impression + theming moat.

**Claude Desktop and MCP Apps (Anthropic's own layer)** — the most existentially adjacent entity. Claude Desktop already connects to your systems via MCP, already schedules, already reasons with Opus 4.7. The January 2026 [MCP Apps](https://blog.modelcontextprotocol.io/posts/2026-01-26-mcp-apps/) initiative even renders UI inside Claude. Meanwhile the Claude iOS app already ships iOS 18+ widgets. *Pro:* The intelligence is world-class and already in users' hands. *Con:* Everything Claude produces stays inside Claude's chat surface (desktop window or in-app). It cannot put a live number on your Lock Screen, cannot fire a push when MRR crosses a threshold, cannot become your Home Screen ambient surface. Our moat against Anthropic is that we own the Apple-ambient-delivery layer that Anthropic has shown no sign of building themselves — *phones are ambient, chat windows are not.*

## Unique Selling Proposition

Only BentoDeck has all five at once:

1. **Conversation-configured, not form-configured.** You tell Claude Desktop what you want to see. Our MCP server receives the spec. Within seconds, the widget is on your phone. No forms, no field mappers, no drag-drop canvas. When you want to change it, you talk to Claude again. This is the interface without a name that "Build For What's Next" is pointing at.

2. **Tier-2 endpoint discovery from natural language.** "Monitor my Linear backlog" — Opus 4.7 reads Linear's docs, picks the right REST endpoint, generates the auth header (using a `{{API_KEY}}` placeholder so the secret never reaches the model), verifies the call before persisting. No hand-maintained connector catalog. Every public API with documentation is a first-class citizen on day one.

3. **Two-tier AI: fast wrist buzz + deep investigation.** A fast Messages-API anomaly call gates on a local z-score and a daily cap to keep cost bounded; the result is the Lock Screen / Live Activity sentence. *In parallel,* a long-running **Claude Managed Agents** session investigates with the full agent toolset (web_search, bash, file ops) and writes a multi-paragraph runbook the user reads when they tap. This is the "decoupling brain from hands" pattern, applied to ops monitoring.

4. **Three Apple ambient surfaces, theme-driven end to end.** iPhone Home Screen widgets (small + medium with sparklines and trend badges), Lock Screen widgets (circular + rectangular + inline), and Live Activities (Lock Screen banner + Dynamic Island compact / minimal / expanded). One AI-generated theme cascades through every surface. We are not a PWA. We are not a browser tab. We live on the surfaces users actually glance at.

5. **AI-themeable UI.** The entire live-data dashboard category has settled on sterile spreadsheet aesthetics — Numerics caps out at a five-option tint picker; Plecto offers a HEX field gated to enterprise customers; Power BI and Grafana IRM give you dark mode and nothing else. Widgetsmith and Widgy went viral on iOS specifically because people want Home Screen surfaces that feel like theirs. BentoDeck brings that energy to live data: 6 preset themes plus a one-prompt AI theme — *"Claude, make it cyberpunk terminal"* → the whole dashboard re-skins in seconds.

The durable framing: **"Claude Desktop's output layer for Apple devices — expressive, conversational, and alive."**

## Scope for v1 (shipped)

**Backend (TypeScript / Node):**
- 14 MCP tools for the conversational config flow.
- REST polling scheduler with cost-bounded AI gating (statistical pre-filter + 20/widget/day cap + value-unchanged short-circuit + anomaly state carry-forward).
- Tier-2 docs-driven endpoint discoverer (`discover_data_source`).
- Opus 4.7 JMESPath transform inference, widget-type picker, anomaly explanation, theme generator.
- **Claude Managed Agents** incident investigator that writes a multi-paragraph runbook in a sandboxed managed container, streamed back and persisted incrementally.
- Production-shaped split: long-running backend (`npm start`) is independent of the MCP thin-client process (`npm run mcp`) Claude Desktop spawns.

**iOS (SwiftUI + WidgetKit):**
- Dashboard list + detail views, theme-driven across the entire surface.
- **6 widget types rendered:** number, number_with_trend (with sparkline + trend badge), gauge (number fallback), sparkline (with chart fill), list, status.
- **3 ambient surfaces:** Home Screen widgets (small + medium), Lock Screen widgets, **Live Activities** (Lock Screen banner + Dynamic Island).
- Tap-to-investigate: anomaly banner / widget tap → InvestigationDetailView that polls and renders the Managed Agents report incrementally as it streams in.
- Background App Refresh + Local Notifications (no APNs — works on free personal team signing).

**Deferred (post-hackathon):**
- Apple Watch complications (requires paid Developer account).
- WebSocket/SSE real-time sources.
- Drag-and-drop canvas, template marketplace.
- Android / Wear OS.
- Action widgets (v1 is read-only).

## Hackathon Context

- **Event:** [Built with Opus 4.7](https://cerebralvalley.ai/e/built-with-4-7-hackathon)
- **Dates:** April 21–26, 2026
- **Submission deadline:** April 26, 2026, 8:00 PM EST
- **Team:** Solo builder + Claude as pair-programmer
- **Target prizes:** Grand prize, "Keep Thinking" ($5k), "Best use of Claude Managed Agents" ($5k)
- **Judging weights:** Impact 30%, Demo 25%, Opus 4.7 Use 25%, Depth 20%

## Quickstart

### Prerequisites

- macOS with Xcode 16+ (tested on Xcode 26.3)
- Node 20+
- Physical iPhone or iOS 17+ simulator
- An Anthropic API key with Opus 4.7 access
- Claude Desktop with MCP support (for the hero flow)
- [xcodegen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

### 1. Backend

```bash
cd server
npm install
cp .env.example .env    # add your ANTHROPIC_API_KEY
npm run dev             # starts HTTP + MCP stdio + mock demo API + poll scheduler
```

The server listens on `http://localhost:3737` for the iOS app, and on
stdio for Claude Desktop's MCP connection.

### 2. iOS

```bash
cd ios
xcodegen generate
open BentoDeck.xcodeproj
```

In Xcode:

1. Select the `BentoDeck` target → **Signing & Capabilities** → set Team to your free personal Apple ID.
2. Do the same for the `BentoDeckWidget` target.
3. If building for a physical iPhone, edit `Sources/Shared/Config.swift` and replace `http://localhost:3737` with your Mac's LAN IP (e.g. `http://192.168.1.42:3737`).
4. Build + run to your iPhone or simulator.
5. Long-press your Home Screen → tap `+` → search "BentoDeck" → add the small or medium widget. (Or the rectangular Lock Screen widget from the Lock Screen customization UI.)

### 3. Claude Desktop (the magical part)

Add BentoDeck to your Claude Desktop MCP config — usually at
`~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "bentodeck": {
      "command": "npx",
      "args": ["tsx", "/absolute/path/to/bentodeck/server/src/index.ts"],
      "env": {
        "ANTHROPIC_API_KEY": "sk-ant-..."
      }
    }
  }
}
```

Restart Claude Desktop. It should list `bentodeck` under your connected MCP servers.

> Only run ONE instance of the backend. If you've started it with `npm run dev`, Claude Desktop will refuse to connect (port conflict). For the clean demo, let Claude Desktop be the launcher — quit `npm run dev` first.

### 4. Talk to Claude

```
Show me Stripe MRR, today's signups, and critical errors
on my Home Screen. Use the /demo/* endpoints on localhost.
```

Claude Desktop calls BentoDeck's MCP tools (`create_dashboard`,
`add_data_source`, `create_widget_from_intent`). Opus 4.7 writes the
JMESPath transforms from the sample responses. Within seconds, widgets
appear in the iOS app and on your Home Screen.

Try follow-ups:

- "Make it cyberpunk." → `generate_theme` kicks in.
- "Pin that to my Lock Screen." → widget appears on Lock Screen.

### 5. The anomaly demo beat

From any terminal while the server is running:

```bash
npm run demo:spike   # from server/ — critical errors jump to 47 for 2 minutes
npm run demo:reset   # from server/ — back to zero
```

Within one poll cycle (≤ 5s), the server sees the spike, Opus 4.7 evaluates
it, flags the snapshot, and your iOS app fires a Local Notification
reading something like "Spike of 47 critical errors in the last 15m…"

## Architecture

See [CLAUDE.md](./CLAUDE.md) for the repo's operational context and scope
rules. High-level:

```
Claude Desktop  ←MCP stdio→  BentoDeck backend  ←HTTP→  iOS app + widgets
       │                       │   │    │
       │                       │   │    └── Opus 4.7 (transforms, themes,
       │                       │   │         anomaly detection + explanation)
       │                       │   └── Poll scheduler + JMESPath engine
       │                       └── Your own REST APIs (Stripe, Supabase,
       │                            whatever) + bundled /demo/* mock
       └── You, in plain English
```

Opus 4.7 runs in seven distinct places across this system — once at
widget creation (JMESPath + widget-type inference), again on every
meaningful snapshot (anomaly decision + one-sentence explanation),
and on demand for AI-generated themes.

## Repo layout

```
bentodeck/
├── README.md           this file — public vision + quickstart
├── CLAUDE.md           operational context for Claude Code
├── LICENSE             MIT
├── server/             TypeScript MCP + HTTP + poller + AI
│   ├── src/
│   │   ├── index.ts
│   │   ├── mcp/        MCP tools exposed to Claude Desktop
│   │   ├── http/       Hono HTTP API for iOS
│   │   ├── ai/         Opus 4.7 clients (setup, anomaly, theme)
│   │   ├── db/         SQLite schema + typed repository
│   │   ├── sources/    REST fetching + JSON sample capping
│   │   ├── scheduler/  Poll loop + anomaly hooks
│   │   ├── themes/     6 preset themes
│   │   └── demo/       Mock Stripe/Supabase/PostHog
│   └── scripts/        seed-demo.ts, smoke-poller.ts
└── ios/                SwiftUI app + WidgetKit extension
    ├── project.yml     xcodegen spec
    └── Sources/
        ├── App/        main target
        ├── Widget/     Home + Lock widgets
        └── Shared/     models used by both targets
```

## License

MIT. See [LICENSE](LICENSE). Open-source from commit one per hackathon
rules.
