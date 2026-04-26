import Foundation

/// What background a dashboard should render. Default is `.theme` — let
/// the loaded theme's `colors.background` show through. `.image` signals
/// that there's an image file at the canonical App Group path
/// `backgrounds/{dashboardId}.jpg` that the app + widget should render.
///
/// We don't put the bytes in this enum — UserDefaults isn't a great place
/// for ~MB-sized photo data — only the *kind*; the bytes live in a file.
enum DashboardBackground: Codable, Hashable {
    case theme
    case image

    static let `default` = DashboardBackground.theme
}

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
    private let dashboardsListKey = "all-dashboards"
    private let perDashboardSnapshotKeyPrefix = "snapshot-"
    private let backgroundKindKeyPrefix = "background-"

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
        // Mirror to the per-dashboard slot so the focus widget's picker has
        // up-to-date data without forcing a separate fetch path.
        saveSnapshot(snapshot, forDashboard: snapshot.dashboardId)
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

    // MARK: - All dashboards (for the focus widget's picker)

    /// Save the lightweight list of dashboards the user has on this device.
    /// Used by the focus widget's AppIntent picker to enumerate options.
    func saveDashboards(_ dashboards: [DashboardSummary]) {
        guard let defaults, let data = try? JSONEncoder().encode(dashboards) else { return }
        defaults.set(data, forKey: dashboardsListKey)
    }

    func loadDashboards() -> [DashboardSummary] {
        guard let defaults,
              let data = defaults.data(forKey: dashboardsListKey),
              let list = try? JSONDecoder().decode([DashboardSummary].self, from: data) else {
            return []
        }
        return list
    }

    /// Per-dashboard snapshot slot. The focus widget reads from here when the
    /// user has picked a specific dashboard in the configuration.
    func saveSnapshot(_ snapshot: SnapshotResponse, forDashboard dashboardId: String) {
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: perDashboardSnapshotKey(dashboardId))
        defaults.set(Date(), forKey: perDashboardSnapshotKey(dashboardId) + "-at")
    }

    func loadSnapshot(forDashboard dashboardId: String) -> (snapshot: SnapshotResponse, at: Date)? {
        guard let defaults,
              let data = defaults.data(forKey: perDashboardSnapshotKey(dashboardId)),
              let snap = try? JSONDecoder().decode(SnapshotResponse.self, from: data) else {
            return nil
        }
        let at = defaults.object(forKey: perDashboardSnapshotKey(dashboardId) + "-at") as? Date ?? Date()
        return (snap, at)
    }

    private func perDashboardSnapshotKey(_ dashboardId: String) -> String {
        perDashboardSnapshotKeyPrefix + dashboardId
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

    // MARK: - Per-dashboard background (Liquid Glass support)

    func loadBackground(dashboardId: String) -> DashboardBackground {
        guard let defaults,
              let data = defaults.data(forKey: backgroundKindKey(dashboardId)),
              let kind = try? JSONDecoder().decode(DashboardBackground.self, from: data) else {
            return .default
        }
        return kind
    }

    func saveBackground(_ kind: DashboardBackground, dashboardId: String) {
        guard let defaults, let data = try? JSONEncoder().encode(kind) else { return }
        defaults.set(data, forKey: backgroundKindKey(dashboardId))
    }

    /// Write a JPEG-encoded photo into the App Group container's
    /// `backgrounds/{dashboardId}.jpg` slot. Both the app and the widget
    /// read from this path. Returns true on success.
    @discardableResult
    func saveBackgroundImage(_ data: Data, dashboardId: String) -> Bool {
        guard let url = backgroundImageURL(dashboardId: dashboardId) else { return false }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    func loadBackgroundImageData(dashboardId: String) -> Data? {
        guard let url = backgroundImageURL(dashboardId: dashboardId),
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    func clearBackgroundImage(dashboardId: String) {
        guard let url = backgroundImageURL(dashboardId: dashboardId) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func backgroundKindKey(_ dashboardId: String) -> String {
        backgroundKindKeyPrefix + dashboardId
    }

    private func backgroundImageURL(dashboardId: String) -> URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Config.appGroupID
        ) else {
            return nil
        }
        return container
            .appendingPathComponent("backgrounds", isDirectory: true)
            .appendingPathComponent("\(dashboardId).jpg")
    }
}
