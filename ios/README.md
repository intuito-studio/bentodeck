# BentoDeck iOS

The native iOS client for BentoDeck. SwiftUI + WidgetKit, free personal team signing.

## Status

Xcode project will be scaffolded in the next milestone. This directory is intentionally minimal for now so the TypeScript backend can be shipped and tested first.

## Planned targets

- **BentoDeck** — main iOS app (SwiftUI). Lists dashboards, shows widget detail views, handles Background App Refresh + Local Notifications.
- **BentoDeckWidget** — WidgetKit extension. Home Screen small + Lock Screen circular/rectangular.
- **BentoDeckShared** — Swift Package for models shared between app and widget.

## How it talks to the backend

The iOS app polls `http://<mac-lan-ip>:3737/dashboards/:id/snapshot` over the local network. For the hackathon demo, the Mac's LAN IP is hardcoded in `Config.swift`. Both targets share an App Group so the widget extension can read the latest snapshot the app fetched.

## Apple dev constraints (locked)

- Free personal team signing (7-day re-sign acceptable for the demo window).
- No paid Apple Developer Program account — no APNs push, no TestFlight.
- Local Notifications replace push for anomaly alerts.
- Apple Watch is **out of scope** for the hackathon submission; deferred to post-hackathon.

## To create the Xcode project (when we get there)

1. Open Xcode 16.
2. File → New → Project → iOS → App.
3. Name: `BentoDeck`. Organization identifier: `com.intuitostudio.bentodeck`. Interface: SwiftUI. Language: Swift. Storage: None.
4. Save into this `ios/` directory.
5. File → New → Target → Widget Extension. Name: `BentoDeckWidget`. Uncheck "Include Configuration App Intent".
6. For both targets: Signing & Capabilities → + Capability → App Groups → `group.com.intuitostudio.bentodeck`.
