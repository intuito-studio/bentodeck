import XCTest
@testable import BentoDeck

/// These tests exercise `SharedStore` against a real `UserDefaults(suiteName:)`.
/// On the simulator this works even without the App Group entitlement — the
/// suite-name initializer falls back to a plain plist in the test host's
/// container. If the initializer ever returns nil (e.g. due to a sandbox
/// change on a future OS), each test gracefully skips rather than failing.
final class SharedStoreTests: XCTestCase {

    private var testSuite: UserDefaults!
    private let snapshotKey = "latest-snapshot-payload"
    private let pinnedKey = "pinned-dashboard-id"

    override func setUp() {
        super.setUp()
        testSuite = UserDefaults(suiteName: "group.com.intuitostudio.bentodeck")
        // Clear any keys that might have leaked in from a previous run.
        testSuite?.removeObject(forKey: snapshotKey)
        testSuite?.removeObject(forKey: snapshotKey + "-at")
        testSuite?.removeObject(forKey: pinnedKey)
    }

    override func tearDown() {
        testSuite?.removeObject(forKey: snapshotKey)
        testSuite?.removeObject(forKey: snapshotKey + "-at")
        testSuite?.removeObject(forKey: pinnedKey)
        testSuite = nil
        super.tearDown()
    }

    func testPinnedDashboardRoundtrip() throws {
        try XCTSkipIf(testSuite == nil, "App Group suite unavailable in this test env")

        let store = SharedStore()
        XCTAssertNil(store.pinnedDashboardId, "Should start empty after setUp cleanup")

        store.savePinnedDashboardId("dash-1")
        XCTAssertEqual(store.pinnedDashboardId, "dash-1")

        store.savePinnedDashboardId("dash-2")
        XCTAssertEqual(store.pinnedDashboardId, "dash-2")
    }

    func testSnapshotRoundtrip() throws {
        try XCTSkipIf(testSuite == nil, "App Group suite unavailable in this test env")

        let store = SharedStore()
        XCTAssertNil(store.loadSnapshot())

        let snapshot = SnapshotResponse(
            dashboardId: "dash-1",
            name: "Indie SaaS",
            themeId: "default",
            theme: Theme.fallback,
            widgets: [
                SnapshotWidget(
                    id: "w-mrr",
                    title: "MRR",
                    type: .number,
                    position: 0,
                    value: SnapshotValue(raw: .number(18420)),
                    anomaly: false,
                    anomalyExplanation: nil,
                    ts: "2026-04-23T12:00:00Z",
                    history: nil,
                    investigationId: nil,
                    investigationStatus: nil
                )
            ]
        )

        store.save(snapshot: snapshot)

        let loaded = store.loadSnapshot()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.snapshot.dashboardId, "dash-1")
        XCTAssertEqual(loaded?.snapshot.widgets.count, 1)
        XCTAssertEqual(loaded?.snapshot.widgets[0].value?.numberValue, 18420)
        // `at` should be recent.
        if let at = loaded?.at {
            XCTAssertLessThan(abs(at.timeIntervalSinceNow), 5,
                              "Saved timestamp should be within a few seconds of now")
        }
    }
}
