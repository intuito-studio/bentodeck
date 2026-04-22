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

Only BentoDeck has all four at once:

1. **Conversation-configured, not form-configured.** You tell Claude Desktop what you want to see. Our MCP server receives the spec. Within seconds, the widget is on your phone. No forms, no field mappers, no drag-drop canvas. When you want to change it, you talk to Claude again. This is the interface without a name that "Build For What's Next" is pointing at.

2. **AI at runtime, not just at setup.** Opus 4.7 generates the data transforms from sample API responses, suggests which widgets are useful, detects anomalies, and explains what happened in plain English when you tap. Every dashboard cell is capable of becoming a conversation.

3. **Native Apple ambient surfaces, first-class.** iPhone Home Screen widgets and Lock Screen are v1. Apple Watch complications and Live Activities are v2. We are not a PWA. We are not a browser tab. We live on the surfaces users actually glance at.

4. **Expressive, AI-themeable UI.** The entire live-data dashboard category has settled on sterile spreadsheet aesthetics — Numerics caps out at a five-option tint picker; Plecto offers a HEX field gated to enterprise customers; Power BI and Grafana IRM give you dark mode and nothing else. Meanwhile Widgetsmith and Widgy went viral on iOS specifically because people want Home Screen surfaces that feel like theirs. BentoDeck brings that energy to live data: 4–6 preset themes at launch, plus a one-prompt AI theme — *"Claude, make it cyberpunk terminal"* → the whole dashboard re-skins in seconds. No prior dashboard product has shipped AI-generated theming for live-data widgets. This is both a demo moment judges remember and a screenshot worth sharing.

The durable framing: **"Claude Desktop's output layer for Apple devices — expressive, conversational, and alive."**

## Scope for v1 (hackathon cut)

**In:**
- TypeScript/Node backend with MCP server exposing dashboard CRUD tools.
- REST polling adapter with API-key auth (first source: Stripe test mode).
- Opus 4.7-generated JMESPath transforms from sample API responses.
- Native iOS app (SwiftUI) with a list of dashboards and widget detail views.
- Home Screen widget (small + medium) and Lock Screen widget via WidgetKit.
- Background App Refresh to update widget timelines.
- Local Notifications triggered when Opus 4.7 detects anomalies (no paid APNs needed).
- Theme system: 4–6 preset themes + one Opus 4.7-generated theme endpoint (colors + font + chart style as JSON; no per-widget styling, no image uploads, no custom fonts).
- Claude Desktop demo: user prompts Claude → MCP call → widget appears on phone in seconds.

**Deferred (post-hackathon):**
- Apple Watch complications (requires paid Developer account + more time than we have).
- WebSocket/SSE real-time sources.
- Live Activities.
- Drag-and-drop canvas, template marketplace.
- Android / Wear OS.
- Action widgets (v1 is read-only monitoring only).

## Hackathon Context

- **Event:** [Built with Opus 4.7](https://cerebralvalley.ai/e/built-with-4-7-hackathon)
- **Dates:** April 21–26, 2026
- **Submission deadline:** April 26, 2026, 8:00 PM EST
- **Team:** Solo builder + Claude as pair-programmer
- **Target prizes:** Grand prize, "Keep Thinking" ($5k), "Best use of Claude Managed Agents" ($5k)
- **Judging weights:** Impact 30%, Demo 25%, Opus 4.7 Use 25%, Depth 20%

## Quickstart

*(To be filled in as we build.)*

## License

MIT. See [LICENSE](LICENSE).
