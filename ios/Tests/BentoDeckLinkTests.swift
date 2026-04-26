import XCTest
@testable import BentoDeck

final class BentoDeckLinkTests: XCTestCase {
    func testDashboardLinkRoundtrip() throws {
        let url = BentoDeckLink.dashboard(id: "abc-123")
        XCTAssertEqual(url.scheme, "bentodeck")
        XCTAssertEqual(url.host, "dashboard")

        let parsed = try XCTUnwrap(BentoDeckLink.parse(url))
        guard case let .dashboard(id) = parsed else {
            return XCTFail("expected .dashboard, got \(parsed)")
        }
        XCTAssertEqual(id, "abc-123")
    }

    func testInvestigationLinkRoundtripWithTitle() throws {
        let url = BentoDeckLink.investigation(
            id: "inv-1",
            widgetTitle: "Critical errors (15m)"
        )
        let parsed = try XCTUnwrap(BentoDeckLink.parse(url))
        guard case let .investigation(id, title) = parsed else {
            return XCTFail("expected .investigation, got \(parsed)")
        }
        XCTAssertEqual(id, "inv-1")
        XCTAssertEqual(title, "Critical errors (15m)")
    }

    func testParseRejectsForeignSchemes() {
        let url = URL(string: "https://dashboard?id=x")!
        XCTAssertNil(BentoDeckLink.parse(url))
    }

    func testParseRejectsUnknownHosts() {
        let url = URL(string: "bentodeck://nonsense?id=x")!
        XCTAssertNil(BentoDeckLink.parse(url))
    }

    func testDashboardLinkRequiresIdQuery() {
        let url = URL(string: "bentodeck://dashboard")!
        XCTAssertNil(BentoDeckLink.parse(url))
    }

    func testInvestigationDefaultsTitleWhenAbsent() throws {
        let url = URL(string: "bentodeck://investigation?id=x")!
        let parsed = try XCTUnwrap(BentoDeckLink.parse(url))
        guard case let .investigation(_, title) = parsed else {
            return XCTFail("expected .investigation, got \(parsed)")
        }
        XCTAssertEqual(title, "Widget")
    }

    func testDataSourceKeyLinkRoundtripWithName() throws {
        let url = BentoDeckLink.dataSourceKey(
            sourceId: "src-vercel-1",
            sourceName: "vercel"
        )
        XCTAssertEqual(url.host, "data-source-key")

        let parsed = try XCTUnwrap(BentoDeckLink.parse(url))
        guard case let .dataSourceKey(id, name) = parsed else {
            return XCTFail("expected .dataSourceKey, got \(parsed)")
        }
        XCTAssertEqual(id, "src-vercel-1")
        XCTAssertEqual(name, "vercel")
    }

    func testDataSourceKeyLinkRoundtripWithoutName() throws {
        let url = BentoDeckLink.dataSourceKey(
            sourceId: "src-only",
            sourceName: nil
        )
        let parsed = try XCTUnwrap(BentoDeckLink.parse(url))
        guard case let .dataSourceKey(id, name) = parsed else {
            return XCTFail("expected .dataSourceKey, got \(parsed)")
        }
        XCTAssertEqual(id, "src-only")
        XCTAssertNil(name)
    }

    func testDataSourceKeyLinkRequiresIdQuery() {
        let url = URL(string: "bentodeck://data-source-key")!
        XCTAssertNil(BentoDeckLink.parse(url))
    }
}
