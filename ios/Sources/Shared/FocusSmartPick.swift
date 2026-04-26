import Foundation

/// Picks the most-relevant widget for the focus widget when the user
/// hasn't manually selected one. Pure function — lives in Shared (rather
/// than alongside WidgetKit-dependent code) so it's reachable from the
/// app target's unit tests.
///
/// Order of preference:
///   1. The first widget with `anomaly == true`
///   2. The widget with the most-recent `ts` (ISO-8601 string compare)
///   3. The widget at position 0 if all else is equal
enum FocusSmartPick {
    static func pick(from widgets: [SnapshotWidget]) -> SnapshotWidget? {
        if widgets.isEmpty { return nil }
        if let anomalous = widgets.first(where: \.anomaly) { return anomalous }
        let sorted = widgets.sorted { (a, b) in
            switch (a.ts, b.ts) {
            case let (l?, r?): return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.position < b.position
            }
        }
        return sorted.first ?? widgets.first
    }
}
