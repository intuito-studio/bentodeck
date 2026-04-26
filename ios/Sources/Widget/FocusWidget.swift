import SwiftUI
import WidgetKit
import AppIntents

/// Resolves the (snapshot, widget) pair the focus widget should render.
///
/// This is the heart of "smart pick": if the user hasn't configured a
/// dashboard or widget, fall back to the most-relevant one we can find.
/// Order of preference for the widget:
///   1. Anomaly with `anomaly == true`
///   2. Most-recent `ts`
///   3. Position 0
enum FocusResolver {
    static func resolve(intent: BentoDeckFocusIntent) -> (snapshot: SnapshotResponse?, widget: SnapshotWidget?, refreshedAt: Date?) {
        let store = SharedStore.shared
        // Pick a dashboard.
        let resolvedSnapshot: (snapshot: SnapshotResponse, at: Date)?
        if let d = intent.dashboard, let pair = store.loadSnapshot(forDashboard: d.id) {
            resolvedSnapshot = pair
        } else if let pinnedId = store.pinnedDashboardId,
                  let pair = store.loadSnapshot(forDashboard: pinnedId) {
            resolvedSnapshot = pair
        } else {
            resolvedSnapshot = store.loadSnapshot()
        }

        guard let resolvedSnapshot else {
            return (nil, nil, nil)
        }
        let snapshot = resolvedSnapshot.snapshot
        let refreshedAt = resolvedSnapshot.at

        // Pick a widget within that dashboard.
        let widget: SnapshotWidget?
        if let chosen = intent.widget,
           let match = snapshot.widgets.first(where: { $0.id == chosen.id }) {
            widget = match
        } else {
            widget = FocusSmartPick.pick(from: snapshot.widgets)
        }

        return (snapshot, widget, refreshedAt)
    }

}

struct FocusEntry: TimelineEntry {
    let date: Date
    let snapshot: SnapshotResponse?
    let widget: SnapshotWidget?
    let theme: Theme
    let refreshedAt: Date?
    let configuration: BentoDeckFocusIntent
    let background: DashboardBackground
    let backgroundImageData: Data?

    var useGlass: Bool { background == .image && backgroundImageData != nil }

    static var placeholder: FocusEntry {
        FocusEntry(
            date: Date(),
            snapshot: nil,
            widget: nil,
            theme: .fallback,
            refreshedAt: nil,
            configuration: BentoDeckFocusIntent(),
            background: .theme,
            backgroundImageData: nil
        )
    }
}

/// AppIntent-driven timeline provider so the widget knows which dashboard +
/// widget the user picked when they configured it.
struct FocusTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> FocusEntry { .placeholder }

    func snapshot(for configuration: BentoDeckFocusIntent, in _: Context) async -> FocusEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: BentoDeckFocusIntent, in _: Context) async -> Timeline<FocusEntry> {
        let now = entry(for: configuration)
        let nextRefresh = Date().addingTimeInterval(15 * 60)
        return Timeline(entries: [now], policy: .after(nextRefresh))
    }

    private func entry(for configuration: BentoDeckFocusIntent) -> FocusEntry {
        let resolved = FocusResolver.resolve(intent: configuration)
        let store = SharedStore.shared
        let bg: DashboardBackground
        let bgData: Data?
        if let dashId = resolved.snapshot?.dashboardId {
            bg = store.loadBackground(dashboardId: dashId)
            bgData = bg == .image ? store.loadBackgroundImageData(dashboardId: dashId) : nil
        } else {
            bg = .theme
            bgData = nil
        }
        return FocusEntry(
            date: resolved.refreshedAt ?? Date(),
            snapshot: resolved.snapshot,
            widget: resolved.widget,
            theme: resolved.snapshot?.theme ?? .fallback,
            refreshedAt: resolved.refreshedAt,
            configuration: configuration,
            background: bg,
            backgroundImageData: bgData
        )
    }
}

/// One BentoDeck widget pinned at full size. Configurable: pick a dashboard
/// and/or a specific widget, or leave both blank for the smart pick.
struct FocusWidget: Widget {
    let kind = "FocusWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: BentoDeckFocusIntent.self,
            provider: FocusTimelineProvider()
        ) { entry in
            FocusView(
                widget: entry.widget,
                theme: entry.theme,
                lastRefreshedAt: entry.refreshedAt,
                useGlass: entry.useGlass
            )
            .containerBackground(for: .widget) {
                FocusWidgetBackground(entry: entry)
            }
            .widgetURL(deepLink(for: entry))
        }
        .configurationDisplayName("BentoDeck — Focus")
        .description("Pin one widget at full size. Leave the picker blank for a smart pick (anomaly first, then most-recent).")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }

    private struct FocusWidgetBackground: View {
        let entry: FocusEntry
        var body: some View {
            ZStack {
                Color(hex: entry.theme.colors.background)
                if entry.background == .image,
                   let data = entry.backgroundImageData,
                   let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                    Color.black.opacity(0.25)
                }
            }
        }
    }

    /// Tap → land on the widget's parent dashboard so the user can drill in.
    /// If the focused widget has an open investigation, deep-link straight to
    /// the report instead.
    private func deepLink(for entry: FocusEntry) -> URL? {
        if let widget = entry.widget,
           let invId = widget.investigationId {
            return BentoDeckLink.investigation(id: invId, widgetTitle: widget.title)
        }
        if let dashId = entry.snapshot?.dashboardId {
            return BentoDeckLink.dashboard(id: dashId)
        }
        return nil
    }
}
