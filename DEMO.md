# BentoDeck — Demo Recording Guide

Everything you need to record the 3-minute hackathon submission video, from
a fresh clone to "stop recording."

> If you only read one section: **Pre-flight checklist** below, then **The 3-minute script** at the bottom. Everything in between is the "from zero" setup that you do once.

---

## Pre-flight checklist (do this 30 minutes before recording)

- [ ] Backend up: `cd server && npm start` — wait for `HTTP listening on http://localhost:3737`
- [ ] `curl -sS http://localhost:3737/health` returns `{"ok":true,...}`
- [ ] Anomaly state reset: `npm run demo:reset` from `server/`
- [ ] Demo dashboard seeded: `npm run seed-demo` (creates "SaaS Health" with 3 widgets)
- [ ] iOS app is installed on the device or simulator and shows the 3-widget dashboard
- [ ] BentoDeck widgets are placed on the Home Screen + Lock Screen of the recording device
- [ ] Claude Desktop has `bentodeck` listed under MCP servers (settings → connectors)
- [ ] Anthropic API key has Opus 4.7 access and at least a few dollars of credit
- [ ] Recording app is running (QuickTime → New Movie / Screen Recording, or Loom)
- [ ] Phone is on Do Not Disturb to suppress unrelated banners
- [ ] Wi-Fi is stable; hotspot off; unrelated terminals closed

If any item fails, fix it now — none of these are recoverable mid-recording.

---

## Setup from zero (one-time, takes ~10 minutes)

### 1. Clone + install

```bash
git clone https://github.com/<your-fork>/bentodeck.git
cd bentodeck
brew install xcodegen          # if you don't have it
```

### 2. Backend

```bash
cd server
npm install
cp .env.example .env
```

Edit `.env`:

```bash
ANTHROPIC_API_KEY=sk-ant-...   # Opus 4.7 key
BENTODECK_HTTP_PORT=3737
BENTODECK_DATA_DIR=./data
```

Confirm it starts cleanly:

```bash
npm start
# → SQLite initialized at data/bentodeck.sqlite
# → Poll scheduler running (tick=5000ms)
# → HTTP listening on http://localhost:3737
```

Leave this terminal running. The backend is a single long-lived Node process —
SQLite, HTTP, the poller, the AI calls. **Don't** also run `npm run dev`; it
will compete with the running instance.

### 3. iOS

In a new terminal:

```bash
cd ios
xcodegen generate
open BentoDeck.xcodeproj
```

In Xcode:

1. Select the **BentoDeck** target → **Signing & Capabilities** → set Team to your free personal Apple ID.
2. Repeat for the **BentoDeckWidget** target (same team — App Groups must match).
3. **For a physical iPhone:** open `Sources/Shared/Config.swift` and change `http://localhost:3737` to your Mac's LAN IP (e.g. `http://192.168.1.42:3737`). Find the IP with `ipconfig getifaddr en0`.
4. **For the simulator:** leave `localhost`. Pick "iPhone 17 Pro" as the destination.
5. `⌘R` — first launch installs the widget extension; this can take 30–60 seconds.
6. On a real phone, accept the "Untrusted Developer" prompt: Settings → General → VPN & Device Management → trust.

### 4. Place widgets on the Home Screen + Lock Screen

**Home Screen:**

1. Long-press an empty space → tap `+` (top-left)
2. Search "BentoDeck" — you'll see two widgets:
   - **BentoDeck** — multi-widget tile grid (Small / Medium / Large / Extra-Large)
   - **BentoDeck — Focus** — single widget at full size
3. For the recording I recommend placing both: a Medium grid widget *and* a Large Focus widget.
4. After dropping the Focus widget, long-press it → **Edit Widget** → leave the picker on "Auto" + "Smart" (it will pick the anomalous widget when one fires).

**Lock Screen:**

1. Long-press the Lock Screen → **Customize** → **Lock Screen**
2. Tap the widget area below the clock → tap an empty slot → search "BentoDeck"
3. Pick the rectangular widget. (Circular and inline are also available.)

### 5. Claude Desktop

Edit `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "bentodeck": {
      "command": "npx",
      "args": ["tsx", "/absolute/path/to/bentodeck/server/src/mcp-entry.ts"],
      "env": {
        "BENTODECK_BASE_URL": "http://localhost:3737"
      }
    }
  }
}
```

Replace `/absolute/path/to` with your real path (`pwd` from `bentodeck/`
prints it). Save the file. **Quit Claude Desktop completely** (`⌘Q` — the
menu-bar quit, not just closing the window) and relaunch.

Verify the connection: in a fresh chat, type "what MCP tools do I have?" —
you should see BentoDeck tools (`create_dashboard`, `add_data_source`,
`create_widget_from_intent`, `generate_theme`, `discover_data_source`,
`get_investigation`, etc.) listed.

### 6. Seed the hero demo dashboard

```bash
cd server
npm run seed-demo
# → created dashboard id=…
# → widgets: Stripe MRR, Signups today, Critical errors (15m)
```

Open the iOS app, pull-to-refresh the dashboard list, tap into "SaaS Health".
You should see three live widgets with values updating every 5s.

---

## Demo control commands

These are the buttons you press during recording. All of them work
regardless of what Claude Desktop is doing.

```bash
cd server

# Spike critical errors to 47 for ~2 minutes — fires the anomaly
npm run demo:spike

# Reset everything (no spike, MRR back to baseline)
npm run demo:reset

# Seed a polished investigation report into the latest anomaly
# (streams in over ~3.5s — used for the recorded video to avoid
# waiting 30–60s for a real Managed Agents session)
npm run demo:seed-investigation
```

> The seeded investigation report has the same shape Opus 4.7's
> investigator system prompt produces; it's a recording aid, not a fake.
> The real Managed Agents path runs end-to-end in production demos.

---

## The 3-minute script

The submission video is 3 minutes. The locked story has 6 beats; if
something breaks live, skip beat 3 (Tier-2 discovery) — it's the only
optional one.

### Beat 0 — Cold open (0:00–0:10)

> *Camera on you, or on the iPhone Home Screen.*

**Say:** "I check my SaaS dashboard 30 times a day. It's always trapped behind a login on a laptop. Today I'm going to put it on my iPhone Home Screen — by talking to Claude."

**Do:** Show the iPhone Home Screen with the BentoDeck widgets visible. Tap into the iOS app to show the empty/ready state.

### Beat 1 — Conversation → live widget (0:10–0:55)

> *Cut to Claude Desktop on screen.*

**Type into Claude Desktop:**

```
Show me Stripe MRR, today's signups, and critical errors on my Home
Screen. Use the /demo/* endpoints on localhost:3737.
```

**What you'll see:**

- Claude calls `create_dashboard` → `add_data_source` (×3) → `create_widget_from_intent` (×3)
- Each `create_widget_from_intent` shows Opus 4.7 inferring the JMESPath transform from the sample API response
- Claude reports back the widget IDs

**Cut to phone:** pull-to-refresh in the BentoDeck app — the new dashboard
appears within ~5s. Tap into "SaaS Health". The bento grid auto-arranges
the three widgets: wide Stripe MRR on top, two squares (Signups, Errors)
below.

**Say:** "Three widgets. No forms. Opus 4.7 wrote the JMESPath transforms by reading the sample response."

### Beat 2 — Theming (0:55–1:25)

**Type into Claude Desktop:**

```
Make it retro trading floor — green-on-black terminal aesthetic.
```

**What you'll see:**

- Claude calls `generate_theme`
- Opus 4.7 emits a complete WCAG-checked theme JSON
- Claude reports the theme is applied

**Cut to phone:** the dashboard re-skins live. Cards, fonts, sparkline
colors, anomaly chip — everything updates without a relaunch.

**Say:** "One sentence. The whole dashboard re-skinned. The Lock Screen widget too — same theme cascades to every surface."

### Beat 3 — Tier-2 discovery (1:25–1:55) *[optional, skip if running short]*

**Type into Claude Desktop:**

```
Also monitor my Linear backlog count.
```

**What you'll see:**

- Claude calls `discover_data_source` with the docs URL
- Opus 4.7 reads Linear's REST docs, picks the right endpoint, generates the auth header with a `{{API_KEY}}` placeholder
- The endpoint is verified against a test request before being persisted
- A new widget appears

**Say:** "No connector catalog. Any public API with documentation works on day one."

### Beat 4 — Anomaly fires (1:55–2:25)

> *Switch to a second terminal you've kept ready.*

**Run:**

```bash
npm run demo:spike
```

**What you'll see (within 5–10s):**

1. Server log: `[anomaly] errors widget z=∞ → AI call`
2. iPhone gets a Local Notification: *"Critical errors spiked from 0 → 47 against a 15-minute zero baseline"*
3. Lock Screen Live Activity appears with the same sentence
4. Dynamic Island shows the compact representation

**Cut to phone:** show the Lock Screen banner. Then tap the Live Activity
to open the app.

**Say:** "Z-score gate, 20-call-per-day cap, value-unchanged short-circuit. Opus 4.7 only writes the sentence when something genuinely changed. Projected cost: 15 cents per user per month."

### Beat 5 — Tap-to-investigate, streaming runbook (2:25–2:50)

> *In the recorded version, run `npm run demo:seed-investigation` in your other terminal RIGHT BEFORE you tap. The pre-canned report has the same shape the real Managed Agents session produces but streams in over ~3.5s, perfect for the recording.*

In the app, tap the anomaly banner. The InvestigationDetailView opens
and the multi-paragraph runbook streams in as Markdown:

- Headline ("Critical errors spiked from 0 → 47…")
- "What likely happened" — three causes
- "What to check first" — five action items
- "Blast radius" — SLO impact

**Say:** "While the wrist-buzz fires, a Claude Managed Agent is investigating in a sandboxed container with web_search, bash, and file tools. By the time I look, the runbook is here."

### Beat 6 — Loop back (2:50–3:00)

> *Cut back to Claude Desktop.*

**Type:**

```
What does the investigation say? Suggest a mitigation.
```

**What you'll see:**

- Claude calls `get_investigation`
- Summarizes the report, suggests a fix (typically: flip the feature flag, check the deploy timestamp)

**Say (closing line):** "Conversation, ambient surface, deep investigation, conversation. That's the loop. BentoDeck is open source. Link in the description."

---

## If something goes wrong on camera

| Symptom | Fast recovery |
|---|---|
| Widget shows old data | Pull-to-refresh in the app |
| Widget shows "Backend returned HTTP 404" | The pinned dashboard ID is stale — back out to the list, tap into a dashboard again |
| Anomaly doesn't fire | Run `npm run demo:reset` then `npm run demo:spike` again |
| Live Activity doesn't appear | Foreground the app once after the spike — first activity request needs the app to be active |
| Investigation doesn't stream | Run `npm run demo:seed-investigation` *before* tapping the banner |
| Claude Desktop shows MCP error | `pwd` in the server folder, ensure the path in `claude_desktop_config.json` matches, ⌘Q Claude Desktop, relaunch |
| Theme didn't apply | The theme generator can take 5–10s on first call (cold cache); just wait for Claude's reply |

---

## Polish details that read well on camera

- Long-press a card in-app → drag the corner to resize. Shows the bento grid + Liquid Glass ghost preview. Looks like the iPhone Home Screen people already know.
- After theming, scrub the Lock Screen and Home Screen widgets to show the theme cascade.
- Pick a photo as the dashboard background (… menu → Background → Choose photo). Cards become Liquid Glass over the photo. Same treatment propagates to the Home Screen widgets within ~10s.
- Add the **Focus widget** to the Home Screen with picker on "Smart". When the anomaly fires, the Focus widget swaps to show the errors widget at full size automatically — visible proof of the smart-pick logic.

---

## Submission checklist

- [ ] Recording uploaded to YouTube (unlisted is fine) or Loom
- [ ] Repo URL on screen at the end of the video
- [ ] [SUBMISSION.md](./SUBMISSION.md) updated with prize-track mapping
- [ ] Repo is **public** before the deadline
- [ ] LICENSE is MIT and present at the repo root
- [ ] Submission form filled in on the hackathon site

Good luck. 🎬
