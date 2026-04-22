import Foundation

/// App-Group-backed persistence the main app writes and the widget extension
/// reads. Widgets cannot make arbitrary network calls on their own in a timely
/// way, so the app fetches fresh snapshots on Background App Refresh and writes
/// them here; the widget's TimelineProvider reads them.
struct SharedStore {
    static let shared = SharedStore()

    private let defaults: UserDefaults?
    private let lastSnapshotKey = "latest-snapshot-payload"
    private let pinnedDashboardIdKey = "pinned-dashboard-id"

    init() {
        self.defaults = UserDefaults(suiteName: Config.appGroupID)
    }

    func savePinnedDashboardId(_ id: String) {
        defaults?.set(id, forKey: pinnedDashboardIdKey)
    }

    var pinnedDashboardId: String? {
        defaults?.string(forKey: pinnedDashboardIdKey)
    }

    func save(snapshot: SnapshotResponse) {
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: lastSnapshotKey)
        defaults.set(Date(), forKey: lastSnapshotKey + "-at")
    }

    func loadSnapshot() -> (snapshot: SnapshotResponse, at: Date)? {
        guard let defaults,
              let data = defaults.data(forKey: lastSnapshotKey),
              let snap = try? JSONDecoder().decode(SnapshotResponse.self, from: data) else {
            return nil
        }
        let at = defaults.object(forKey: lastSnapshotKey + "-at") as? Date ?? Date()
        return (snap, at)
    }
}
