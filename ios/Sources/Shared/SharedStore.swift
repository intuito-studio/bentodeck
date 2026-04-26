import Foundation

/// Per-dashboard layout customization the user has made on this device.
/// Stored alongside the cached snapshot in the App Group UserDefaults so
/// the app survives a relaunch with the same arrangement.
///
/// `customized` flips to `true` the first time the user touches the layout
/// (resize, in v1). Once true, BentoDeck stops auto-arranging this dashboard:
/// any new widget that arrives is appended at `.small` instead of triggering
/// the 1/2/3-widget auto-layout.
struct DashboardLayoutState: Codable, Hashable {
    var customized: Bool
    var sizeOverrides: [String: LayoutSize]   // widgetId → size

    static let empty = DashboardLayoutState(customized: false, sizeOverrides: [:])
}

/// App-Group-backed persistence the main app writes and the widget extension
/// reads. Widgets cannot make arbitrary network calls on their own in a timely
/// way, so the app fetches fresh snapshots on Background App Refresh and writes
/// them here; the widget's TimelineProvider reads them.
struct SharedStore {
    static let shared = SharedStore()

    private let defaults: UserDefaults?
    private let lastSnapshotKey = "latest-snapshot-payload"
    private let pinnedDashboardIdKey = "pinned-dashboard-id"
    private let layoutStateKeyPrefix = "dashboard-layout-"

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

    // MARK: - Per-dashboard layout state

    func loadLayoutState(dashboardId: String) -> DashboardLayoutState {
        guard let defaults,
              let data = defaults.data(forKey: layoutStateKey(dashboardId)),
              let state = try? JSONDecoder().decode(DashboardLayoutState.self, from: data) else {
            return .empty
        }
        return state
    }

    func saveLayoutState(_ state: DashboardLayoutState, dashboardId: String) {
        guard let defaults, let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: layoutStateKey(dashboardId))
    }

    func resetLayoutState(dashboardId: String) {
        defaults?.removeObject(forKey: layoutStateKey(dashboardId))
    }

    private func layoutStateKey(_ dashboardId: String) -> String {
        layoutStateKeyPrefix + dashboardId
    }
}
