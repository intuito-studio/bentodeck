import XCTest
@testable import BentoDeck

final class InvestigationTests: XCTestCase {

    /// Mirrors `GET /investigations/:id` returned by the server's
    /// http/routes.ts — wraps the row in `{ "investigation": {...} }`.
    private let runningJSON = """
    {
      "investigation": {
        "id": "inv-1",
        "widgetId": "w-errors",
        "snapshotId": 42,
        "sessionId": "ses_xyz",
        "status": "running",
        "title": null,
        "report": "## Headline\\n\\nWe're getting started…",
        "error": null,
        "createdAt": "2026-04-26T12:00:00Z",
        "completedAt": null
      }
    }
    """.data(using: .utf8)!

    private let doneJSON = """
    {
      "investigation": {
        "id": "inv-2",
        "widgetId": "w-errors",
        "snapshotId": null,
        "sessionId": "ses_2",
        "status": "done",
        "title": "Critical errors spiked from 0 → 47",
        "report": "## Critical errors spiked from 0 → 47\\n\\nFull body here.",
        "error": null,
        "createdAt": "2026-04-26T12:00:00Z",
        "completedAt": "2026-04-26T12:01:00Z"
      }
    }
    """.data(using: .utf8)!

    private let failedJSON = """
    {
      "investigation": {
        "id": "inv-3",
        "widgetId": "w-errors",
        "snapshotId": null,
        "sessionId": null,
        "status": "failed",
        "title": null,
        "report": null,
        "error": "rate limited",
        "createdAt": "2026-04-26T12:00:00Z",
        "completedAt": "2026-04-26T12:00:05Z"
      }
    }
    """.data(using: .utf8)!

    private let listJSON = """
    {
      "investigations": [
        {
          "id": "inv-2",
          "widgetId": "w-errors",
          "snapshotId": null,
          "sessionId": "ses_2",
          "status": "done",
          "title": "X",
          "report": "...",
          "error": null,
          "createdAt": "2026-04-26T12:00:00Z",
          "completedAt": "2026-04-26T12:00:30Z"
        },
        {
          "id": "inv-1",
          "widgetId": "w-errors",
          "snapshotId": null,
          "sessionId": "ses_1",
          "status": "running",
          "title": null,
          "report": null,
          "error": null,
          "createdAt": "2026-04-26T11:55:00Z",
          "completedAt": null
        }
      ]
    }
    """.data(using: .utf8)!

    func testDecodesRunningInvestigation() throws {
        let wrapped = try JSONDecoder().decode(InvestigationResponse.self, from: runningJSON)
        let inv = wrapped.investigation
        XCTAssertEqual(inv.id, "inv-1")
        XCTAssertEqual(inv.widgetId, "w-errors")
        XCTAssertEqual(inv.snapshotId, 42)
        XCTAssertEqual(inv.sessionId, "ses_xyz")
        XCTAssertEqual(inv.status, "running")
        XCTAssertNil(inv.title)
        XCTAssertNotNil(inv.report)
        XCTAssertFalse(inv.isTerminal)
        XCTAssertNil(inv.completedAt)
    }

    func testDecodesDoneInvestigation() throws {
        let wrapped = try JSONDecoder().decode(InvestigationResponse.self, from: doneJSON)
        let inv = wrapped.investigation
        XCTAssertEqual(inv.status, "done")
        XCTAssertEqual(inv.title, "Critical errors spiked from 0 → 47")
        XCTAssertTrue(inv.isTerminal)
        XCTAssertNotNil(inv.completedAt)
    }

    func testDecodesFailedInvestigation() throws {
        let wrapped = try JSONDecoder().decode(InvestigationResponse.self, from: failedJSON)
        let inv = wrapped.investigation
        XCTAssertEqual(inv.status, "failed")
        XCTAssertEqual(inv.error, "rate limited")
        XCTAssertTrue(inv.isTerminal)
    }

    func testIsTerminalForUnknownStatus() throws {
        let json = runningJSON // running == not terminal
        let wrapped = try JSONDecoder().decode(InvestigationResponse.self, from: json)
        XCTAssertFalse(wrapped.investigation.isTerminal)
    }

    func testDecodesInvestigationList() throws {
        let resp = try JSONDecoder().decode(
            InvestigationListResponse.self, from: listJSON
        )
        XCTAssertEqual(resp.investigations.count, 2)
        XCTAssertEqual(resp.investigations[0].id, "inv-2")
        XCTAssertEqual(resp.investigations[0].status, "done")
        XCTAssertEqual(resp.investigations[1].id, "inv-1")
        XCTAssertEqual(resp.investigations[1].status, "running")
    }
}
