import XCTest
@testable import BentoDeck

final class LayoutSizeTests: XCTestCase {
    func testCellsForEachSize() {
        XCTAssertEqual(LayoutSize.small.cols, 1)
        XCTAssertEqual(LayoutSize.small.rows, 1)
        XCTAssertEqual(LayoutSize.wide.cols, 2)
        XCTAssertEqual(LayoutSize.wide.rows, 1)
        XCTAssertEqual(LayoutSize.tall.cols, 1)
        XCTAssertEqual(LayoutSize.tall.rows, 2)
        XCTAssertEqual(LayoutSize.large.cols, 2)
        XCTAssertEqual(LayoutSize.large.rows, 2)
    }

    func testCycleOrderIsClosed() {
        // small → wide → large → tall → small (the order the resize handle walks)
        XCTAssertEqual(LayoutSize.small.next, .wide)
        XCTAssertEqual(LayoutSize.wide.next, .large)
        XCTAssertEqual(LayoutSize.large.next, .tall)
        XCTAssertEqual(LayoutSize.tall.next, .small)

        // Four cycles always lands back where it started.
        for start in LayoutSize.allCases {
            var s = start
            for _ in 0..<4 { s = s.next }
            XCTAssertEqual(s, start)
        }
    }
}

final class BentoAutoLayoutTests: XCTestCase {
    func testEmptyDashboard() {
        XCTAssertEqual(BentoLayout.defaultSizes(count: 0), [])
    }

    func testOneWidgetIsLarge() {
        // One widget should fill the screen — large is 2×2, the biggest cell.
        XCTAssertEqual(BentoLayout.defaultSizes(count: 1), [.large])
    }

    func testTwoWidgetsStackWideOverWide() {
        XCTAssertEqual(BentoLayout.defaultSizes(count: 2), [.wide, .wide])
    }

    func testThreeWidgetsAreWideThenTwoSmall() {
        // Hero on top, two squares on the second row.
        XCTAssertEqual(BentoLayout.defaultSizes(count: 3), [.wide, .small, .small])
    }

    func testFourWidgetsAreFourSmalls() {
        XCTAssertEqual(BentoLayout.defaultSizes(count: 4), [.small, .small, .small, .small])
    }

    func testManyWidgetsAreAllSmall() {
        let sizes = BentoLayout.defaultSizes(count: 9)
        XCTAssertEqual(sizes.count, 9)
        XCTAssertTrue(sizes.allSatisfy { $0 == .small })
    }
}

final class BentoPackerTests: XCTestCase {
    func testPacksAutoLayoutForThreeWidgets() {
        let items: [(id: String, size: LayoutSize)] = [
            ("a", .wide), ("b", .small), ("c", .small),
        ]
        let packed = BentoLayout.pack(items)
        XCTAssertEqual(packed.count, 3)

        let a = packed.first { $0.id == "a" }!
        XCTAssertEqual(a.cell.col, 0)
        XCTAssertEqual(a.cell.row, 0)

        let b = packed.first { $0.id == "b" }!
        XCTAssertEqual(b.cell.row, 1)
        XCTAssertEqual(b.cell.col, 0)

        let c = packed.first { $0.id == "c" }!
        XCTAssertEqual(c.cell.row, 1)
        XCTAssertEqual(c.cell.col, 1)

        XCTAssertEqual(BentoLayout.rowCount(packed), 2)
    }

    func testPacksLargeFollowedByTwoSmalls() {
        // large (2×2) takes the whole top, then two smalls go to row 2.
        let packed = BentoLayout.pack([
            ("hero", .large), ("b", .small), ("c", .small),
        ])
        let hero = packed.first { $0.id == "hero" }!
        XCTAssertEqual(hero.cell.col, 0)
        XCTAssertEqual(hero.cell.row, 0)

        let b = packed.first { $0.id == "b" }!
        XCTAssertEqual(b.cell.row, 2)
        XCTAssertEqual(b.cell.col, 0)
        let c = packed.first { $0.id == "c" }!
        XCTAssertEqual(c.cell.row, 2)
        XCTAssertEqual(c.cell.col, 1)

        XCTAssertEqual(BentoLayout.rowCount(packed), 3)
    }

    func testPacksTallNextToSmalls() {
        // tall (1×2) on the left, two smalls stack on the right.
        let packed = BentoLayout.pack([
            ("t", .tall), ("a", .small), ("b", .small),
        ])
        let t = packed.first { $0.id == "t" }!
        XCTAssertEqual(t.cell.col, 0)
        XCTAssertEqual(t.cell.row, 0)

        let a = packed.first { $0.id == "a" }!
        XCTAssertEqual(a.cell.col, 1)
        XCTAssertEqual(a.cell.row, 0)

        let b = packed.first { $0.id == "b" }!
        XCTAssertEqual(b.cell.col, 1)
        XCTAssertEqual(b.cell.row, 1)

        XCTAssertEqual(BentoLayout.rowCount(packed), 2)
    }

    func testPackerIsOrderPreserving() {
        // 5 smalls — should fill row 0, row 1, row 2, in input order.
        let packed = BentoLayout.pack([
            ("a", .small), ("b", .small), ("c", .small), ("d", .small), ("e", .small),
        ])
        let byId = Dictionary(uniqueKeysWithValues: packed.map { ($0.id, $0.cell) })
        XCTAssertEqual(byId["a"], GridCell(col: 0, row: 0, size: .small))
        XCTAssertEqual(byId["b"], GridCell(col: 1, row: 0, size: .small))
        XCTAssertEqual(byId["c"], GridCell(col: 0, row: 1, size: .small))
        XCTAssertEqual(byId["d"], GridCell(col: 1, row: 1, size: .small))
        XCTAssertEqual(byId["e"], GridCell(col: 0, row: 2, size: .small))
    }
}

final class DashboardLayoutPersistenceTests: XCTestCase {
    private var testSuite: UserDefaults!
    private let dashboardId = "dash-layout-test"

    override func setUp() {
        super.setUp()
        testSuite = UserDefaults(suiteName: "group.com.intuitostudio.bentodeck")
        testSuite?.removeObject(forKey: "dashboard-layout-\(dashboardId)")
    }

    override func tearDown() {
        testSuite?.removeObject(forKey: "dashboard-layout-\(dashboardId)")
        testSuite = nil
        super.tearDown()
    }

    func testRoundtripPerDashboardLayoutState() throws {
        try XCTSkipIf(testSuite == nil, "App Group suite unavailable in this test env")

        let store = SharedStore()

        // Empty by default.
        let initial = store.loadLayoutState(dashboardId: dashboardId)
        XCTAssertFalse(initial.customized)
        XCTAssertTrue(initial.sizeOverrides.isEmpty)

        // Save a customized state.
        let saved = DashboardLayoutState(
            customized: true,
            sizeOverrides: ["w-mrr": .large, "w-signups": .small]
        )
        store.saveLayoutState(saved, dashboardId: dashboardId)

        let loaded = store.loadLayoutState(dashboardId: dashboardId)
        XCTAssertTrue(loaded.customized)
        XCTAssertEqual(loaded.sizeOverrides["w-mrr"], .large)
        XCTAssertEqual(loaded.sizeOverrides["w-signups"], .small)
    }

    func testResetClearsLayoutState() throws {
        try XCTSkipIf(testSuite == nil, "App Group suite unavailable in this test env")

        let store = SharedStore()
        let saved = DashboardLayoutState(customized: true, sizeOverrides: ["w-1": .tall])
        store.saveLayoutState(saved, dashboardId: dashboardId)

        XCTAssertTrue(store.loadLayoutState(dashboardId: dashboardId).customized)

        store.resetLayoutState(dashboardId: dashboardId)
        let after = store.loadLayoutState(dashboardId: dashboardId)
        XCTAssertFalse(after.customized)
        XCTAssertTrue(after.sizeOverrides.isEmpty)
    }

    func testPerDashboardLayoutStatesAreIndependent() throws {
        try XCTSkipIf(testSuite == nil, "App Group suite unavailable in this test env")

        let store = SharedStore()
        let other = "dash-other"
        defer { testSuite?.removeObject(forKey: "dashboard-layout-\(other)") }

        store.saveLayoutState(
            DashboardLayoutState(customized: true, sizeOverrides: ["a": .large]),
            dashboardId: dashboardId
        )
        store.saveLayoutState(
            DashboardLayoutState(customized: true, sizeOverrides: ["a": .small]),
            dashboardId: other
        )

        XCTAssertEqual(store.loadLayoutState(dashboardId: dashboardId).sizeOverrides["a"], .large)
        XCTAssertEqual(store.loadLayoutState(dashboardId: other).sizeOverrides["a"], .small)

        store.resetLayoutState(dashboardId: dashboardId)
        XCTAssertFalse(store.loadLayoutState(dashboardId: dashboardId).customized)
        XCTAssertTrue(store.loadLayoutState(dashboardId: other).customized,
                      "Resetting one dashboard must not touch another")
    }
}
