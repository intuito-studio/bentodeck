# BentoDeck — Demo Recording Guide

Everything you need to record the 3-minute hackathon submission video, from
a fresh clone to "stop recording."

> If you only read one section: **Pre-flight checklist** below, then **The 3-minute script** at the bottom. Everything in between is the "from zero" setup that you do once.

---

## Pre-flight checklist (do this 30 minutes before recording)

- Backend up: `cd server && npm start` — wait for `HTTP listening on http://localhost:3737`
- `curl -sS http://localhost:3737/health` returns `{"ok":true,...}`
- Anomaly state reset: `npm run demo:reset` from `server/`
- Demo dashboard seeded: `npm run seed-demo` (creates "SaaS Health" with 3 widgets)
- iOS Simulator running (iPhone 17 Pro) with the app installed and the 3-widget dashboard visible
- BentoDeck widgets are placed on the simulator's Home Screen + Lock Screen
- Claude has `bentodeck` listed under MCP servers (settings → connectors)
- Anthropic API key has Opus 4.7 access and at least a few dollars of credit
- Screen recording is running (QuickTime → File → New Screen Recording, or Loom) with system audio + mic capture
- Mic is on the right input; do a 5-second test recording and play it back
- macOS notifications muted (Focus → Do Not Disturb) so banners don't intrude on the recording
- Unrelated apps quit; only the simulator, Claude, two terminals, and the recorder are open
- Wi-Fi is stable; unrelated terminals closed

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
3. Pick **iPhone 17 Pro** as the destination (it has Dynamic Island, which Beat 4 relies on). Leave `Sources/Shared/Config.swift` pointing at `http://localhost:3737`.
4. `⌘R` — first launch installs the widget extension; this can take 30–60 seconds.

### 4. Place widgets on the Home Screen + Lock Screen

> Everything below happens inside the iOS Simulator. Use **click-and-hold** wherever it says "long-press." Useful simulator shortcuts: `⌘L` to lock, `⇧⌘H` for the Home Screen, `⌘1` / `⌘2` / `⌘3` to scale the window.

**Home Screen (in the simulator):**

1. Click-and-hold an empty space → tap `+` (top-left)
2. Search "BentoDeck" — you'll see two widgets:
  - **BentoDeck** — multi-widget tile grid (Small / Medium / Large / Extra-Large)
  - **BentoDeck — Focus** — single widget at full size
3. For the recording I recommend placing both: a Medium grid widget *and* a Large Focus widget.
4. After dropping the Focus widget, click-and-hold it → **Edit Widget** → leave the picker on "Auto" + "Smart" (it will pick the anomalous widget when one fires).

**Lock Screen (in the simulator):**

1. `⌘L` to lock, then click-and-hold the Lock Screen → **Customize** → **Lock Screen**
2. Tap the widget area below the clock → tap an empty slot → search "BentoDeck"
3. Pick the rectangular widget. (Circular and inline are also available.)

### 5. Claude

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
prints it). Save the file. **Quit Claude completely** (`⌘Q` — the
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
regardless of what Claude is doing.

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

The submission video is 3 minutes. **Assume the judge knows nothing
about your stack** — not Claude, not MCP, not iOS widgets.
Every beat earns its existence by either showing something or
explaining the thing that's about to happen, never both.

The locked story has 6 beats. If something breaks live, skip beat 3
(Tier-2 discovery) — it's the only optional one. Trim 5 seconds from
each remaining beat to recover.

> **Tone note:** read everything below as if to a friend who's never
> seen the project. Conversational, not pitch-y. Don't say "leveraging."
> Don't say "powered by." Say what you did and what happened.

### Beat 0 — Who I am, what hurts (0:00–0:25)

> *Voiceover only — no face on camera. The whole video is a screen
> recording.*
>
> **On screen:** a desktop crowded with 6 browser tabs already open —
> Vercel, Firebase console, GCP console, a billing dashboard, an error
> tracker, a CI pipeline. Slowly cycle Cmd+ (or click) through 3–4 of
> them so the judge sees the chaos. Then `⇧⌘H` in the iOS Simulator and
> let the camera land on a clean Simulator Home Screen with the BentoDeck
> widgets present but empty / awaiting data.

**Say (slow, natural, as voiceover):**

> "I'm Morris. I run Intuito Studio. We build custom software solutions  
> for clients, so on any given day I'm running four or five different  
> systems across different projects. Some live on Vercel, some on  
> Firebase, some on GCP — plus the billing dashboards, the error  
> trackers, the CI pipelines. I check all of those probably thirty times  
> a day. They live in browser tabs on my laptop. None of them are on my  
> phone, because every vendor's app has its own login, its own UI, its  
> own headache.
>
> So I built BentoDeck. I tell Claude what I want to see, and it ends up
> on my iPhone Home Screen. Let me show you."

### Beat 1 — Conversation → live widget (0:25–1:05)

> *Cut to Claude. Make sure the BentoDeck MCP server is visible
> in the connectors panel before you start typing — judges should see
> "this is wired up to something real."*

**Say first, before typing:**

> "Claude talks to my BentoDeck server through MCP — that's the
> protocol that lets Claude call into outside systems. Watch what
> happens when I just describe what I want."

**Type into Claude:**

```
Show me Stripe MRR, today's signups, and critical errors on my
Home Screen. Use the /demo/ endpoints on localhost.
```

**While Claude works (15–20 seconds), narrate over the tool calls:**

> "Claude is creating a dashboard, registering three data sources, and
> for each one it's hitting the API once to grab a sample response.
> Then Opus 4.7 reads that sample and writes the transformation that
> pulls out the right number — no field-mapping forms, no config UI."

**Cut to the simulator (let Claude's tool calls finish off-screen — judges
follow the artifact, not the process):**

- Pull-to-refresh in the BentoDeck app → "SaaS Health" appears
- Tap in. The bento grid auto-arranges: wide Stripe MRR card on top,
two squares (Signups · Errors) below
- `⇧⌘H` to the Home Screen for a half-second to show the home-screen
widget already populated with the same numbers

**Say:**

> "Three widgets. Thirty seconds. No forms."

### Beat 2 — Theming (1:05–1:30)

> *Back to Claude.*

**Say first:**

> "It looks fine. But it's mine, and I want it to feel like mine.
> Watch this."

**Type:**

```
Make it look like Anthropic — warm cream background, soft terracotta
accents, the Claude vibe. Friendly serif for the numbers if it works.
```

**Cut to the simulator before Claude is fully done.** The theme cascade
is the visual punchline — let it happen on screen.

- Cards re-skin: cream/ivory background, terracotta accent, warm tones
- Lock Screen widget re-skins to match
- Home Screen widget re-skins to match

**Say:**

> "One sentence. Opus 4.7 wrote a full color theme — checked the contrast
> ratios for accessibility — and it cascaded everywhere. The app, the
> Home Screen widget, the Lock Screen widget. Same theme, every surface.
> A nice meta-touch: the dashboard now looks like the model that
> generated it."

### Beat 3 — Add Vercel, no token in chat (1:30–1:55) *[optional, skip if running short]*

> *Back to Claude.* Callback to Beat 0 — the judge already heard you
> mention Vercel; now it's hooked up live.
>
> **Pre-flight:** generate a Vercel API token from
> [vercel.com/account/tokens](https://vercel.com/account/tokens) and
> have it on your clipboard. You'll paste it into the iOS app, never
> into Claude.

**Say first:**

> "Earlier I mentioned Vercel. BentoDeck doesn't ship a Vercel
> connector — I'll just point Claude at the docs. And notice I'm not
> giving Claude my API token."

**Type (no token in the prompt):**

```
Also show me my latest Vercel deployments. Here are the API docs:
https://vercel.com/docs/rest-api/reference/endpoints/deployments
```

**Cut to the simulator.** A new "Vercel deployments" card lands on the
dashboard with a lock icon and "Tap to add API key."

**Tap the card.** A SecureField sheet slides up. Paste, tap Save. The
sheet dismisses; the card flips to live deployment data.

**Say (over the verify → live-data transition):**

> "Token goes straight into the app, never through the chat. Any public
> API with docs works on day one — same path would handle GitHub,
> Linear, PostHog, whatever you point at it."

### Beat 4 — Anomaly detected, live on the dashboard (1:55–2:25)

> *Stay in the iOS app on the Home dashboard. Switch to your second
> terminal — kept ready, already in `server/`.*

**Say first:**

> "Okay, the dashboard's pretty. Here's why I actually built this."

**Run:**

```bash
npm run demo:spike
```

**Within 5–10 seconds, on the dashboard:**

1. The Critical errors widget flips from `ZERO` (green) to `47` with a
  red warning triangle in the top-right of the card.
2. Tap the card — the anomaly sentence Claude wrote appears underneath:
  *"Critical errors spiked from 0 → 47 against a 15-minute zero
  baseline."*

**Say:**

> "The server polled the source on its own  
> schedule, saw the spike, ran it past a cost gate, and only then asked  
> Claude to explain it. There's a statistical pre-filter so idle drift  
> doesn't burn API budget — projected cost is fifteen cents per user  
> per month, even though every anomaly sentence is a live Opus 4.7 call."

### Beat 5 — Tap → Managed Agent investigation (2:25–2:50)

> *Right before you tap the banner, run `npm run demo:seed-investigation`
> in your second terminal so the report streams in deterministically.
> The shape matches what the real Managed Agents session produces; the
> recording trick is just timing.*

**Tap the anomaly banner on the Critical errors card.**

**As the report streams in (~3.5 seconds), narrate:**

> "While the banner fired, a separate Claude Managed Agent went off to
> investigate. It's running in a sandboxed cloud container with web
> search, bash, and file tools. It's not a chat completion — it's a
> long-running session. By the time I tap, the report is already
> writing itself."

**Let the headline land on screen:** *"Critical errors spiked from
0 → 47 against a 15-minute zero baseline."* Then "What likely
happened," then "What to check first," then "Blast radius."

### Beat 6 — Close the loop (2:50–3:00)

> *Cut back to Claude.*

**Type:**

```
What does the investigation say? Suggest a mitigation.
```

**Claude reads the report and recommends a fix.**

**Say (final line, voiceover over the chat):**

> "Conversation in. Glance out. Investigation in. Conversation out.
> That's the loop. BentoDeck is open source — link's below."

> *End on the repo URL on screen for 2 seconds.*

---

## Phrase bank — what to say if you go off-script

When something stalls and you need filler that *adds value* instead of
sounding like an apology:

- *"While that's loading, let me say what's happening under the hood…"*
→ buy 8–10 seconds with a one-line technical explainer.
- *"I should mention — none of this is hardcoded. The server doesn't know
what 'MRR' means. Opus 4.7 figures that out from the API response."*
- *"This is what Anthropic calls Managed Agents. It's a different API
surface from the chat completions you might've seen — these sessions
can run for minutes."*
- *"The whole thing is open source. MIT license. The repo's in the
description."*

## If something goes wrong on camera


| Symptom                                          | Fast recovery                                                                                                    |
| ------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| Widget shows old data                            | Pull-to-refresh in the app                                                                                       |
| Widget shows "Backend returned HTTP 404"         | The pinned dashboard ID is stale — back out to the list, tap into a dashboard again                              |
| Anomaly doesn't fire                             | Run `npm run demo:reset` then `npm run demo:spike` again                                                         |
| Live Activity doesn't appear                     | Foreground the app once after the spike — first activity request needs the app to be active                      |
| Investigation doesn't stream                     | Run `npm run demo:seed-investigation` *before* tapping the banner                                                |
| Claude shows MCP error                           | `pwd` in the server folder, ensure the path in `claude_desktop_config.json` matches, ⌘Q Claude, relaunch         |
| Theme didn't apply                               | The theme generator can take 5–10s on first call (cold cache); just wait for Claude's reply                      |
| Vercel "Connect" card doesn't appear             | Pull-to-refresh the dashboard. The discoverer takes ~10–15s to fetch + parse Vercel's docs before the row lands. |
| Vercel key fails to save (HTTP 401 in the sheet) | Token is rejected — generate a fresh one at vercel.com/account/tokens. The card stays in needs-key state.        |
| You forget your line                             | Pause, breathe, look at the screen. The artifact does the talking. The judges already saw what happened.         |


---

## Polish details that read well on camera

- Long-press a card in-app → drag the corner to resize. Shows the bento grid + Liquid Glass ghost preview. Looks like the iPhone Home Screen people already know.
- After theming, scrub the Lock Screen and Home Screen widgets to show the theme cascade.
- Pick a photo as the dashboard background (… menu → Background → Choose photo). Cards become Liquid Glass over the photo. Same treatment propagates to the Home Screen widgets within ~10s.
- Add the **Focus widget** to the Home Screen with picker on "Smart". When the anomaly fires, the Focus widget swaps to show the errors widget at full size automatically — visible proof of the smart-pick logic.

---

## Submission checklist

- Recording uploaded to YouTube (unlisted is fine) or Loom
- Repo URL on screen at the end of the video
- [SUBMISSION.md](./SUBMISSION.md) updated with prize-track mapping
- Repo is **public** before the deadline
- LICENSE is MIT and present at the repo root
- Submission form filled in on the hackathon site

Good luck. 🎬

