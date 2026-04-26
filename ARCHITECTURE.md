# BentoDeck — Architecture

This is a living reference for how BentoDeck is wired internally. The
[`README.md`](./README.md) covers the product vision; this doc covers
the implementation.

## System overview

```
┌────────────────────────────────────────────────────────────────────────┐
│                              YOUR MAC                                    │
│                                                                          │
│   ┌──────────────┐      stdio      ┌─────────────────────────┐          │
│   │Claude Desktop│◀────MCP────────▶│ BentoDeck MCP thin      │          │
│   │  (Opus 4.7)  │                  │ client (mcp-entry.ts)   │          │
│   └──────────────┘                  │ — translates tool calls │          │
│                                     │   to HTTP, no DB, no AI │          │
│                                     └─────────────┬───────────┘          │
│                                                   │ HTTP (localhost)     │
│                                                   ▼                      │
│                                     ┌─────────────────────────┐          │
│                                     │ BentoDeck backend       │          │
│                                     │ (npm start, always-on)  │          │
│                                     │  • Hono HTTP API        │          │
│                                     │  • Poll scheduler       │          │
│                                     │  • Anomaly cost gate    │          │
│                                     │  • SQLite (WAL)         │          │
│                                     │  • Anthropic SDK        │──────────────┐
│                                     └─────────────┬───────────┘          │   │
│                                                   │ HTTP (LAN IP)        │   │
└───────────────────────────────────────────────────┼──────────────────────┘   │
                                                    │                          │
       ┌────────────────────────────────────────────┼────────────────────┐     │
       │                  iPhone (Wi-Fi)            │                    │     │
       │                                            ▼                    │     │
       │   ┌──────────────────┐         ┌──────────────────────┐         │     │
       │   │ BentoDeck app    │────────▶│ App Group store      │         │     │
       │   │ (SwiftUI)        │         │ (UserDefaults suite) │         │     │
       │   │ — RefreshManager │         └──────────┬───────────┘         │     │
       │   │ — DashboardDetail│                    │ reads timeline      │     │
       │   │ — InvestigationUI│                    ▼                     │     │
       │   └────────┬─────────┘         ┌──────────────────────┐         │     │
       │            │ fires             │ Widget extension     │         │     │
       │            ▼                   │ (WidgetKit)          │         │     │
       │   ┌──────────────────┐         │  • Home Screen S/M   │         │     │
       │   │ Local Notif      │         │  • Lock Screen wids  │         │     │
       │   │ (anomaly)        │         │  • Live Activities   │         │     │
       │   └──────────────────┘         └──────────────────────┘         │     │
       │   ┌──────────────────┐                                          │     │
       │   │ Live Activity    │                                          │     │
       │   │ (Lock + Dynamic  │                                          │     │
       │   │  Island)         │                                          │     │
       │   └──────────────────┘                                          │     │
       └────────────────────────────────────────────────────────────────┘     │
                                                                              │
                                  ┌─────────────────────────────┐             │
                                  │ EXTERNAL SERVICES            │             │
                                  │  • Anthropic Messages API    │◀────────────┤
                                  │  • Claude Managed Agents     │◀────────────┤
                                  │  • User's data sources       │             │
                                  │    (Stripe, Linear, own API) │◀────────────┘
                                  └─────────────────────────────┘
```

The split between the always-on backend (`npm start`) and the per-conversation
MCP thin client (`npm run mcp`, spawned by Claude Desktop) is deliberate. It's
the same shape a hosted SaaS would have: one backend, many short-lived MCP
clients connecting over HTTP. Both processes are included in this repo so the
hackathon demo runs locally; in production the backend moves to Fly / Railway /
Render and the thin client stays on the user's Mac.

## Setup flow (Claude Desktop builds your widget)

```
USER (at Mac)               CLAUDE DESKTOP          MCP THIN CLIENT      BENTODECK BACKEND           OPUS 4.7              iOS APP / WIDGET
────────────                ──────────────          ───────────────      ─────────────────           ────────────────      ────────────────
"Show Stripe MRR,
 signups, errors on
 my Home Screen"     ─────▶ (Opus 4.7 plans)
                            create_dashboard
                            ──────────────────────▶ POST /dashboards   ▶ (persist)
                            ◀──────────────────────  { dashboard }     ◀
                            add_data_source ×3
                            ──────────────────────▶ POST /data-sources ▶ (persist)
                            create_widget_from_intent ×3
                            ──────────────────────▶ POST /dashboards/x
                                                         /widgets/from-intent
                                                                       │
                                                                       ▶ fetch sample
                                                                         from data source
                                                                       │
                                                                       ▶ planWidget()
                                                                         intent + sample
                                                                       ────────────▶ Opus 4.7
                                                                                       (JMESPath +
                                                                                        widget type +
                                                                                        title)
                                                                       ◀────────────
                                                                       │
                                                                       ▶ persist widget
                                                                         + initial snapshot
                            ◀──────────────────────  { widget, plan, preview }                                     pull snapshot
                                                                                                                   render
                                                                                                                   home screen widget
                     ◀───── "Done. Live on your phone."
```

## Runtime loop (poll → cost gate → anomaly → wrist buzz → investigation)

```
                    ┌──────────────────────────────────────────────────────────┐
                    │                   BACKEND POLL TICK (every 5s)            │
                    │                                                            │
   USER's APIs ─────┼──▶ pollSource(source, widgets):                            │
   (Stripe, etc.)   │      fetch URL → JSON                                      │
                    │      for each subscribed widget:                           │
                    │        value = jmespath(json, widget.transformExpr)        │
                    │        prev = latestSnapshot(widget)                       │
                    │        if value === prev.value:                            │
                    │            ┌────────────────────────────┐                  │
                    │            │ if prev.anomaly:           │                  │
                    │            │   carry-forward — write    │                  │
                    │            │   new snapshot row keeping │                  │
                    │            │   the anomaly flag set     │                  │
                    │            │ else:                      │                  │
                    │            │   write new snapshot       │                  │
                    │            └────────────────────────────┘                  │
                    │            (no AI call — value unchanged)                  │
                    │            continue                                        │
                    │        else:                                               │
                    │            write new snapshot                              │
                    │            checkAnomalyForWidget(value):                   │
                    │              if recent.length < 4: return                  │
                    │              gate = shouldInvokeAnomalyAI(...):            │
                    │                if |z-score| < 2.5: SKIP                    │
                    │                if daily-cap exceeded: SKIP                 │
                    │              ───┐                                          │
                    │                 │                                          │
                    │                 ▼                                          │
                    │         evaluateAnomaly() ──────▶ Opus 4.7 Messages API    │
                    │            (1-sentence wrist                               │
                    │             buzz explanation)                              │
                    │         markLatestSnapshotAnomaly(...)                     │
                    │         spawnInvestigation() ──┐                           │
                    └────────────────────────────────┼──────────────────────────┘
                                                    │
                                                    ▼
                              ┌─────────────────────────────────────────┐
                              │ runInvestigation():                      │
                              │   ensureAgentAndEnvironment() (cached)   │
                              │   sessions.create()                      │
                              │   stream agent.message events,           │
                              │   persist report incrementally           │
                              │   ───────────────────────────────────────▶ Claude Managed Agents
                              │       agent_toolset_20260401              │  (web_search, bash,
                              │       (Opus 4.7 in container)             │   file ops in cloud
                              │       on session.status_idle: done        │   container)
                              │                                          │
                              └──────────────────┬──────────────────────┘
                                                 │
                              ┌──────────────────┴──────────────────────┐
                              │                  iOS                      │
                              │                                            │
                              │   RefreshManager.refresh()                 │
                              │     • fetch /dashboards/:id/snapshot       │
                              │     • SharedStore.save(snapshot)           │
                              │     • WidgetCenter.reloadAllTimelines()    │
                              │     • LiveActivityManager.reconcile()      │
                              │       starts/updates/ends Live Activity    │
                              │     • if anomaly → fire Local Notification │
                              │                                            │
                              └────────────────────────────────────────────┘
```

## Where Opus 4.7 lives

| #  | Call site                                | What                                                | Frequency                  | Tier              |
|----|------------------------------------------|-----------------------------------------------------|----------------------------|-------------------|
| 1  | Setup agent — JMESPath inference          | Sample JSON + intent → JMESPath                     | Once per widget creation   | Messages          |
| 2  | Setup agent — widget-type picker         | Same call as (1); chooses one of 6 widget types     | Once per widget creation   | Messages          |
| 3  | Setup agent — widget naming              | Same call as (1); short title (≤40 chars)           | Once per widget creation   | Messages          |
| 4  | Tier-2 endpoint discovery                | Docs URL + intent + key → REST spec                 | Once per source creation   | Messages          |
| 5  | Theme generator                          | Vibe prompt → complete theme JSON                   | On user request            | Messages          |
| 6  | Anomaly detector                         | Recent series + current value → flag + explanation  | Per gate-pass poll tick    | Messages (cached) |
| 7  | Anomaly explanation                      | Same call as (6); ≤140-char wrist sentence          | Per gate-pass poll tick    | Messages (cached) |
| 8  | Managed Agents incident investigator     | Multi-paragraph runbook in a sandboxed container    | Per anomaly fire           | **Managed Agents**|
| 9  | Claude Desktop orchestration             | Decides which MCP tools to call, when, with what    | Continuous in conversation | Messages (Claude) |

## Cost-control gate

`server/src/scheduler/anomaly-gate.ts` sits between the poll loop and any Opus
call. It applies, in order:

1. **Value-unchanged short-circuit** (in `poller.ts` before the gate is
   reached): if the new value equals the previous snapshot value, no AI call.
2. **Statistical pre-filter:** compute `|z| = |x - μ| / σ` over the last 24
   numeric points. Skip when `|z| < 2.5`. Returns `Infinity` for
   zero-variance series (so a step from 0 to 47 always passes).
3. **Per-widget daily cap:** sliding 24h window of timestamps per widget;
   max 20 calls/day. (Tunable; production free tier would drop to ~5/day.)
4. **Anomaly state carry-forward** (in `poller.ts` after the gate): when a
   value is unchanged AND the previous snapshot was anomalous, copy the
   anomaly_flag + explanation into the new snapshot row so persistent
   spikes stay surfaced in iOS.

Outcome: idle drift on a metric pays $0 in AI cost; a real spike fires
exactly once and persists across subsequent identical polls until the value
recovers.

## Two-tier AI architecture

```
                                ┌─────────────────────────────────┐
                                │           ANOMALY FIRES         │
                                └────────────┬────────────────────┘
                                             │
                          ┌──────────────────┴──────────────────┐
                          ▼                                     ▼
              ┌────────────────────┐              ┌──────────────────────────┐
              │ TIER 1 (fast)      │              │ TIER 2 (deep)            │
              │ Messages API call  │              │ Managed Agents session   │
              │ ≤140-char sentence │              │ multi-paragraph runbook  │
              │ < 1 second         │              │ 30–60 seconds            │
              │ $0.012 per call    │              │ $0.10–0.50 per session   │
              │ Wrist buzz         │              │ Tap-to-read in app       │
              │ Lock Screen banner │              │                          │
              └────────────────────┘              └──────────────────────────┘
                          │                                     │
                          └──────────────┬──────────────────────┘
                                         ▼
                      Both surface in the iOS UI:
                       • Tier 1 → Local Notification + Live Activity
                       • Tier 2 → Investigation banner pill →
                         InvestigationDetailView (polls /investigations/:id
                         every 1.5s; renders Markdown sections; shows
                         partial reports as they stream in)
```

The decoupling matters: the wrist buzz never blocks on the slow tier, and the
expensive investigation never re-runs on subsequent polls of the same anomaly.

## SQLite schema

```
dashboards         — id, name, theme_id, created_at
data_sources       — id, name, type, url, method, headers_json,
                      auth_header_key, auth_header_value, poll_interval_sec,
                      last_sample_json, created_at
widgets            — id, dashboard_id, source_id, type, title,
                      transform_expr, position, created_at
snapshots          — id (autoinc), widget_id, value_json, anomaly_flag,
                      anomaly_explanation, ts
themes             — id, name, is_preset, json, created_at
investigations     — id, widget_id, snapshot_id, session_id, status,
                      title, report, error, created_at, completed_at
kv                 — key, value (e.g. cached Managed Agents agent_id +
                      environment_id)
```

`snapshots` queries always tiebreak on `id DESC` after `ts DESC` because
SQLite's `datetime('now')` has 1-second resolution and the poll cadence is
faster than that. AUTOINCREMENT id is the strict tiebreaker.

## iOS process model

The app and the widget extension share one App Group container. The app
fetches snapshots, persists them, and reloads the widget timelines; the
widget extension reads from the App Group when iOS asks for a timeline. The
widget never makes network calls of its own.

Background App Refresh fires `BGAppRefreshTask` on Apple's schedule. When
it does, `RefreshManager.refresh()` runs:

1. Fetch the pinned dashboard's snapshot.
2. Persist it to the App Group.
3. Reload widget timelines via `WidgetCenter.shared.reloadAllTimelines()`.
4. `LiveActivityManager.reconcile(snapshot)` — start a Live Activity for
   every newly-anomalous widget, update the state on existing ones, end
   activities for widgets that recovered.
5. Fire a Local Notification for any anomalies (replaces APNs push;
   works on free personal team).

## Test surface

```
server (Vitest)                ~1.4s        116 tests across 13 files
ios (XCTest)                   ~14s         81 tests across 8 files
e2e (bash + curl + jq)         ~13s         16 assertions
```

The E2E script (`scripts/e2e-smoke.sh`) is the canonical pre-demo gate. It
spins a clean SQLite, seeds the demo dashboard, boots the backend, asserts
initial values, fires a spike, waits for propagation, asserts the spike
landed, seeds an investigation, waits for it to stream to `done`, asserts
the snapshot endpoint surfaces the investigation pointer, then resets and
tears the backend down. Idempotent.
