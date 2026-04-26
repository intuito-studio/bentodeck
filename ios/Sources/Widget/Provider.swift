import Foundation
import WidgetKit

struct BentoEntry: TimelineEntry {
    let date: Date
    let snapshot: SnapshotResponse?
    let theme: Theme
    let background: DashboardBackground
    let backgroundImageData: Data?

    var useGlass: Bool { background == .image && backgroundImageData != nil }

    static let placeholder = BentoEntry(
        date: Date(),
        snapshot: nil,
        theme: .fallback,
        background: .theme,
        backgroundImageData: nil
    )
}

/// Reads the latest snapshot the app wrote into the shared App Group store
/// and emits two timeline entries: the current one plus one ~15 minutes out
/// to encourage iOS to refresh us.
struct BentoTimelineProvider: TimelineProvider {
    func placeholder(in _: Context) -> BentoEntry {
        BentoEntry.placeholder
    }

    func getSnapshot(in _: Context, completion: @escaping (BentoEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(
        in _: Context,
        completion: @escaping (Timeline<BentoEntry>) -> Void
    ) {
        let now = currentEntry()
        let nextRefresh = Date().addingTimeInterval(15 * 60)
        let timeline = Timeline(entries: [now], policy: .after(nextRefresh))
        completion(timeline)
    }

    private func currentEntry() -> BentoEntry {
        let store = SharedStore.shared
        guard let (snapshot, at) = store.loadSnapshot() else {
            return BentoEntry(
                date: Date(),
                snapshot: nil,
                theme: .fallback,
                background: .theme,
                backgroundImageData: nil
            )
        }
        let dashboardId = snapshot.dashboardId
        let bg = store.loadBackground(dashboardId: dashboardId)
        let bgData = bg == .image ? store.loadBackgroundImageData(dashboardId: dashboardId) : nil
        return BentoEntry(
            date: at,
            snapshot: snapshot,
            theme: snapshot.theme ?? .fallback,
            background: bg,
            backgroundImageData: bgData
        )
    }
}
