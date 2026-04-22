# BentoDeck — Submission for Built with Opus 4.7

## Project name

**BentoDeck** — Claude Desktop's output layer for Apple devices.

## One-line pitch

Tell Claude what you want to see. It's on your iPhone Home Screen in 30 seconds — and Claude tells you in plain English on your Lock Screen when something goes wrong.

## Written summary (≤ 200 words)

BentoDeck closes the gap between Claude Desktop's conversational intelligence and Apple's ambient glance surfaces. Claude Desktop already connects to Stripe, Supabase, PostHog, and countless other systems via MCP — but its outputs are stranded inside the chat window. It can't put a number on your Lock Screen or fire a push to your wrist.

BentoDeck is an MCP server + native iOS + WidgetKit extension that does exactly that. In Claude Desktop you say "Show me Stripe MRR, today's signups, and critical errors on my Home Screen." Claude calls BentoDeck's MCP tools. **Opus 4.7 runs in seven distinct places** across the system — generating JMESPath transforms from sample API responses, picking the right widget type, detecting anomalies in poll history, explaining them in plain English, and on demand, re-theming the entire dashboard from a prompt like *"make it cyberpunk."*

Built solo in ~4.5 days on an Xcode 26.3 + Node 20 stack. Native SwiftUI + WidgetKit, no PWA. Local Notifications replace APNs for free personal team signing. Every live number on your iPhone came from an Opus 4.7 call. Open-source from commit one under MIT.

## Links

- **GitHub repo:** https://github.com/<TBD>/bentodeck
- **Demo video:** https://<TBD> (3-minute, Loom or YouTube)
- **Live domain (informational):** https://bentodeck.io

## Team

Solo builder — Morris / [Intuito Studio](mailto:hello@intuitostudio.com) — paired with Claude Code.

## Judging-criteria mapping

### Impact (30%)

Everyone running a live system — indie SaaS founders, bot traders, AI-app builders, ops engineers — checks their dashboard 10 to 50 times a day, and that dashboard is almost always trapped in a laptop browser tab. The dashboard category's mobile story is weak: Numerics.io caps theming at a five-option tint picker, Power BI Mobile has zero iPhone Home Screen widgets after 5+ years, and Retool Mobile has no widgets or watch support at all. BentoDeck attacks a real daily friction with an Apple-native solution Claude Desktop itself cannot ship. The "Build For What's Next" problem statement fits: an interface that doesn't have a name yet — ambient Claude output on your wrist.

### Demo (25%)

The hero beat is easier to demo than to explain: user types in Claude Desktop, widget appears on the iPhone Home Screen within seconds. Second beat: "make it cyberpunk" — the entire dashboard re-skins live. Third beat: a simulated anomaly fires, a Local Notification lands on the Lock Screen with Opus 4.7's plain-English explanation.

### Opus 4.7 Use (25%)

Opus 4.7 is not a one-off feature — it is the substrate. Call sites:

1. **Setup agent — endpoint + transform inference.** Given a sample API response and a plain-English intent, Opus 4.7 emits a JMESPath expression, picks a widget type, and names the widget. Tool-use API, cached system prompt, JMESPath preview validation before persisting.
2. **Anomaly detector.** On each new snapshot, Opus 4.7 evaluates whether the latest value is anomalous given the rolling history, and if so, writes a one-sentence explanation that ships to the user's Lock Screen.
3. **Theme generator.** Natural-language vibe → complete theme JSON with WCAG-AA contrast checks baked into the system prompt.
4. **Claude Desktop itself.** The entire configuration flow is orchestrated by Opus 4.7 in Claude Desktop, which chooses which MCP tools to call and in what sequence.

Prompt caching is used at every call site to keep latency low during the live demo.

### Depth & Execution (20%)

The system is end-to-end integrated, not demoware:

- TypeScript MCP server + HTTP backend + poll scheduler + SQLite time-series — all boot in a single process.
- JMESPath runs both server-side (poll loop) and is AI-authored with preview validation at creation time.
- Native SwiftUI app + WidgetKit extension sharing an App Group; `xcodebuild` succeeds on Xcode 26.3 SDK.
- Local Notifications, Background App Refresh, and widget timeline reloads are wired into a single `RefreshManager`.
- Six preset themes + AI theme generation, rendered by a single theme-driven view layer on both the app and widget sides.
- End-to-end verified with an included smoke test against a live public API (GitHub) and a demo seeder + mock API + spike control.

## Build log (git history)

```
<will be pasted in once final>
```

## License

MIT.
