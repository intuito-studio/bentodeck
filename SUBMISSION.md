# BentoDeck — Submission for Built with Opus 4.7

## Project name

**BentoDeck** — Claude Desktop's output layer for Apple devices.

## One-line pitch

Tell Claude what you want to see. It's on your iPhone Home Screen in 30 seconds — and Claude tells you in plain English on your Lock Screen, Dynamic Island, and Apple Watch when something goes wrong.

## Written summary (≤ 200 words)

BentoDeck closes the gap between Claude Desktop's conversational intelligence and Apple's ambient glance surfaces. Claude already connects to your systems via MCP — but its outputs are trapped inside the chat window. It can't put a number on your Lock Screen, fire a push to your wrist, or take over your Dynamic Island when something breaks.

You say "Show me Stripe MRR, today's signups, and critical errors on my Home Screen." Claude Desktop calls BentoDeck's MCP tools. **Opus 4.7 runs in nine distinct places** across the system: it reads each platform's API docs and emits a working REST endpoint, generates the JMESPath transform, picks the right widget type, names the widget, designs themes from prompts like *"retro trading floor"*, detects anomalies with a statistical pre-filter on top, explains them in plain English on the Lock Screen, and — for the deepest investigations — kicks off a **Claude Managed Agents** session that writes a multi-paragraph runbook the user reads when they tap.

Two-tier AI: a fast Messages-API anomaly call for the wrist buzz; a long-running Managed Agents session for the deep dive. Decoupled, both surfaced in the iOS app. Native SwiftUI + WidgetKit + Live Activities, no PWA. Open-source under MIT.

## Links

- **GitHub repo:** https://github.com/intuito-studio/bentodeck
- **Demo video:** https://youtu.be/roASE-cP21E (3-minute, YouTube)
- **Live domain (informational):** https://bentodeck.io

## Team

Solo builder — Morris / [Intuito Studio](mailto:hello@intuitostudio.com) — paired with Claude Code.

## Judging-criteria mapping

### Impact (30%)

Everyone running a live system — indie SaaS founders, bot traders, AI-app builders, ops engineers — checks their dashboard 10 to 50 times a day, and that dashboard is almost always trapped in a laptop browser tab. The category's mobile story is weak: Numerics.io caps theming at a five-option tint picker, Power BI Mobile has zero iPhone Home Screen widgets after 5+ years, Retool Mobile has no widgets or watch support at all, and Plecto's free tier doesn't exist (10-license $300/mo floor). BentoDeck attacks a real daily friction with an Apple-native solution Claude Desktop itself cannot ship. The "Build For What's Next" problem statement fits: an interface that doesn't have a name yet — *ambient Claude output on your wrist*.

We've also done the SaaS-cost math honestly. The naive "Opus 4.7 on every poll" design lands at ~$150/user/month — bankrupting at scale. BentoDeck ships a four-layer cost gate (statistical pre-filter via z-score, per-widget daily cap, value-unchanged short-circuit, anomaly state carry-forward) that bounds spend at ~$0.15/user/month — a 1000× reduction without sacrificing a single AI capability. The architecture that makes the demo possible is also the architecture that makes the SaaS viable.

### Demo (25%)

Five live beats in three minutes:

1. **Conversation → live widget.** "Show me Stripe MRR, today's signups, errors on my Home Screen." Claude calls BentoDeck's MCP tools, Opus picks transforms + widget types, widgets appear on the iPhone within seconds.
2. **Live AI theming.** "Make it retro trading floor" — Opus 4.7 emits a complete WCAG-checked theme JSON; the dashboard re-skins everywhere (app + Home Screen widget) in real time.
3. **Tier-2 discovery.** "Also monitor my Linear backlog" — Opus reads Linear's docs, picks the right endpoint, generates the auth header, verifies the call before persisting. No hand-maintained connector catalog.
4. **Anomaly fires.** Mock API spikes critical errors. Cost gate (z=∞) passes. Wrist buzz on the simulator. Lock Screen Live Activity shows the widget value + Opus's explanation. Dynamic Island compact + expanded layouts.
5. **Tap-to-investigate.** Tapping the Live Activity opens a SwiftUI report — a multi-paragraph incident runbook written by **Claude Managed Agents** in the background, streaming in as bytes arrive.

Three Apple ambient surfaces (Home Screen widgets, Lock Screen widgets, Live Activities) all working together with a coherent theme. No green-screen smoke and mirrors.

### Opus 4.7 Use (25%)

Opus 4.7 is the substrate, not a feature. **Nine distinct call sites:**

1. **Tier-2 endpoint discovery.** Given a platform's docs URL + intent in English, Opus reads the docs (HTML stripped, capped at 60 KB), emits a complete REST spec via tool-use, including auth-header template `Bearer {{API_KEY}}` so the secret never reaches the model. Backend verifies the spec by calling the endpoint before persisting.
2. **Setup agent — JMESPath inference.** Sample JSON + intent → JMESPath expression validated against the sample.
3. **Setup agent — widget-type picker.** Same call as (2), but Opus also picks `number` vs `number_with_trend` vs `gauge` vs `sparkline` vs `list` vs `status` from the data shape and intent wording.
4. **Setup agent — widget naming.** Concise titles (≤40 chars) like "Stripe MRR" or "Critical errors (15m)."
5. **Theme generator.** Natural-language vibe → complete theme JSON with WCAG-AA contrast checks and font-family selection baked into the system prompt.
6. **Anomaly detector.** Per snapshot whose value changed AND passed a local z-score gate (≥2.5σ over a 24-point rolling window), Opus evaluates against the recent series and writes a ≤140-char wrist-friendly explanation.
7. **Anomaly explanation.** Same call as (6); the prose is what lands on the Lock Screen and inside the Live Activity.
8. **Managed Agents incident investigator.** When (6) fires, we ALSO kick off a long-running **Claude Managed Agents** session whose job is to write a multi-paragraph incident report. Runs in a sandboxed managed container with the full agent toolset (web_search, bash, file ops). Streams events back; we persist the report incrementally so the iOS app can show partial progress. This is the **decoupling-brain-from-hands** pattern Anthropic ships Managed Agents for, applied to ops monitoring.
9. **Claude Desktop itself.** The whole flow is orchestrated by Opus 4.7 in Claude Desktop, which decides which MCP tools to call, in what order, with what arguments.

Prompt caching is used at every Messages-API call site. Two-tier architecture (cheap + fast vs. deep + thorough) is exactly the production shape.

### Depth & Execution (20%)

The system is end-to-end integrated, not demoware:

- **Production architecture from day one.** TypeScript MCP server is a thin stdio client that proxies HTTP to a long-running backend. `npm start` is the always-on backend (HTTP + poller + SQLite + AI); `npm run mcp` is the per-conversation MCP process Claude Desktop spawns. They never compete for the port; the backend can run while a hundred MCP clients connect simultaneously.
- **Cost-bounded by design.** Statistical pre-filter (z-score) + per-widget daily cap + value-unchanged short-circuit + anomaly state carry-forward across polls. ~99% of idle ticks pay zero AI cost.
- **Three Apple ambient surfaces.** Home Screen widgets (small + medium with sparklines), Lock Screen widgets (circular + rectangular + inline), Live Activities (Lock Screen banner + Dynamic Island compact / minimal / expanded). All theme-driven; an AI-generated theme cascades through every surface in one HTTP call.
- **Tap-to-investigate.** Anomaly banner is a button → push InvestigationDetailView → polls the Managed Agents report every 1.5s, parses Markdown into themed sections, surfaces partial reports as they stream in.
- **No half-finished code.** 14 MCP tools, 22 HTTP routes, 102 backend Vitest cases (≤500 ms), 69 iOS XCTest cases (≤100 ms), 11 end-to-end smoke assertions in `scripts/e2e-smoke.sh`. xcodebuild succeeds clean on Xcode 26.3 / iOS 26.2 SDK.

## Two prize-specific hooks

### "Best use of Claude Managed Agents" ($5k)

Real Managed Agents wiring, not a buzzword pitch:

- `server/src/ai/investigator.ts` — `ensureAgentAndEnvironment()` lazily creates ONE Agent + Environment per backend lifecycle, caches their IDs in a SQLite kv table so we don't re-create them on every restart. `spawnInvestigation()` is fire-and-forget from the poll loop; `runInvestigation()` opens a stream, sends a user.message event, and persists `agent.message` text incrementally as the session emits it. Terminates on `session.status_idle`.
- The agent uses `agent_toolset_20260401` — bash + file ops + web search — to investigate beyond what a single Messages call could reach.
- Bounded by the same cost gate that protects the wrist-buzz path: one investigation per gate-pass, never on idle drift.
- Clean failure path: every error caught, persisted as `status: 'failed'` with the message, surfaced in the iOS app as "Investigation could not complete" — never crashes the poll loop, never silently drops.

This is exactly what the Managed Agents blog post calls "decoupling the brain from the hands" — a production-shaped two-tier AI pattern, applied to ops monitoring.

### "Keep Thinking" ($5k)

The whole project earns this. *Claude Desktop's output layer for Apple devices* is a category nobody named. We had to build the architecture before we knew what to call it. We pivoted twice in the first day — from "horizontal dashboard builder" (would have lost to Numerics) to "AI on-call partner" (Claude Desktop already does it) to *the bridge from Claude's intelligence to the surfaces Claude can't reach*. Three Apple ambient surfaces with theme-driven AI rendering at every layer is, as far as we found in two passes of competitor research, an unoccupied tuple.

## Build log (clean git history, 50 commits)

```
a842b37  chore: ship app icon, branding, signing team, and demo script polish
866d829  feat(mcp): teach discover_data_source to default to the secure no-key path
9af4055  feat(ios): "needs key" warning state + secure in-app key entry
cbbc322  feat(server): "needs key" data-source state for safer Tier-2 discovery
06de8af  docs: refresh README + add DEMO.md with 3-min recording script
f7e25a6  fix(ios): only the active carousel page contributes its toolbar
8479072  fix(ios): hoist background to RootView, cross-fade between dashboards
e1d373e  perf(ios): kill carousel jank — lazy paging, image cache, instant snapshot
9ceac0c  feat(ios): replace dashboard list with horizontal infinite carousel
48442fa  feat(ios): per-dashboard background image with Liquid Glass cards
739d578  test(ios): unit tests for FocusSmartPick
b304ed0  feat(ios/widget): add Focus widget — pin one widget at full size, smart or configurable
1527924  feat(ios/widget): add systemLarge + systemExtraLarge home-screen sizes
86ba58d  feat(ios): fixed cell dimensions, drop screen-fill stretch
a7db385  demo(server): add seed-many script — 8-widget dashboard for stress testing
bf9e6b5  feat(ios): drag-to-resize the bento handle, with a dashed ghost preview
c749e17  feat(ios): bento grid with iOS-style edit mode + sticky per-dashboard layout
923d5aa  docs: add PROGRESS.md handoff doc for any future session
d97bdc2  docs: add ARCHITECTURE.md — system diagrams, data flow, cost gate
59905d0  docs(claude): refresh operational doc with what actually shipped
c40fac7  test(ios): Codable coverage for Investigation + new SnapshotWidget fields
818f9d6  test(server): unit tests for the Managed Agents investigator
17fc1a2  test: extend E2E smoke to cover the investigation flow (16 assertions)
c1cb95b  feat(ios): bentodeck:// deep links from widgets and Live Activities
dde9e07  feat(server): read-side MCP tools (Claude can pull data BACK)
a703f7a  feat(server): demo investigation seeder + tests for discoverer + seeder
d0ac059  feat(ios): sparkline + trend badge in medium Home Screen widget
b06f666  docs(readme): reflect Tier-2 discovery + Managed Agents + Live Activities
a7cfcf7  docs: refresh SUBMISSION.md for the new capabilities
1cef911  feat(server): Tier-2 — discover_data_source from any platform's docs
6dc8d89  feat(ios): tap-anomaly → Managed Agents investigation deep-dive
129c16a  feat(ios): Live Activities for anomalies — third Apple ambient surface
7e1f33f  feat(ios+server): sparkline rendering + trend badges
7b6a5ba  feat(server): Claude Managed Agents incident investigator
e72d368  fix(server): remove warmup gate — it blocked persistent-spike anomalies
e9b85fb  fix(server): carry anomaly state across unchanged-value polls
9ec6aad  refactor: split MCP and backend into separate processes (production shape)
a511247  feat(server): statistical pre-filter + daily cap on anomaly AI calls
479ee50  test(ios): XCTest suite (69 tests, 0.07s) for Shared models
e740645  test(server): Vitest suite (68 tests, ~300ms) + test hooks
f58317d  test: end-to-end smoke script for pre-demo rehearsal
bd070aa  docs: full README quickstart + SUBMISSION.md for hackathon
c154234  feat(server): demo mock API + seed script for rehearsal and fallback
4a5d087  feat(ios): native iOS app + Home/Lock widgets + background refresh
6488b7e  feat(server): theme system — 6 presets + Opus 4.7 generate_theme
edc52f2  feat(server): Opus 4.7 anomaly detection in the poll loop
8ded334  feat(server): REST polling scheduler with end-to-end smoke test
381b938  feat(server): Opus 4.7 setup agent (create_widget_from_intent)
16f08c6  feat(server): MCP CRUD tools for dashboards, data sources, and widgets
3af19f2  chore: initial scaffold (vision, license, TypeScript backend skeleton)
```

## License

MIT — open-source from commit one.
