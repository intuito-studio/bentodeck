import XCTest
@testable import BentoDeck

final class SnapshotResponseTests: XCTestCase {

    /// Mirrors the shape produced by `GET /dashboards/:id/snapshot` in
    /// `server/src/http/server.ts`.
    private let snapshotJSON = """
    {
      "dashboardId": "dash-1",
      "name": "Indie SaaS",
      "themeId": "default",
      "theme": {
        "id": "default",
        "name": "Default",
        "colors": {
          "background": "#0B0B0F",
          "surface": "#17171D",
          "primary": "#F5F5F7",
          "secondary": "#9A9AA5",
          "accent": "#FF7A1A",
          "positive": "#27C26A",
          "negative": "#FF5252",
          "border": "#2A2A33"
        },
        "font": { "family": "default", "weightPrimary": "bold" },
        "chart": { "stroke": "#FF7A1A", "fillStart": "#FF7A1A55", "fillEnd": "#FF7A1A00" }
      },
      "widgets": [
        {
          "id": "w-mrr",
          "title": "MRR",
          "type": "number",
          "position": 0,
          "value": 18420,
          "anomaly": false,
          "anomalyExplanation": null,
          "ts": "2026-04-23T12:00:00Z"
        },
        {
          "id": "w-signups",
          "title": "Today's Signups",
          "type": "number_with_trend",
          "position": 1,
          "value": 42,
          "anomaly": false,
          "anomalyExplanation": null,
          "ts": "2026-04-23T12:00:00Z"
        },
        {
          "id": "w-errors",
          "title": "Error Count",
          "type": "number",
          "position": 2,
          "value": 137,
          "anomaly": true,
          "anomalyExplanation": "Error rate tripled in the last 10 minutes — most errors trace to /api/checkout.",
          "ts": "2026-04-23T12:00:00Z"
        },
        {
          "id": "w-unknown",
          "title": "Future Widget",
          "type": "brand_new_type_2027",
          "position": 3,
          "value": null,
          "anomaly": false,
          "anomalyExplanation": null,
          "ts": null
        }
      ]
    }
    """.data(using: .utf8)!

    func testDecodesTopLevelFields() throws {
        let resp = try JSONDecoder().decode(SnapshotResponse.self, from: snapshotJSON)
        XCTAssertEqual(resp.dashboardId, "dash-1")
        XCTAssertEqual(resp.name, "Indie SaaS")
        XCTAssertEqual(resp.themeId, "default")
        XCTAssertNotNil(resp.theme)
        XCTAssertEqual(resp.theme?.id, "default")
        XCTAssertEqual(resp.widgets.count, 4)
    }

    func testDecodesFirstWidgetWithNumberValue() throws {
        let resp = try JSONDecoder().decode(SnapshotResponse.self, from: snapshotJSON)
        let w = resp.widgets[0]
        XCTAssertEqual(w.id, "w-mrr")
        XCTAssertEqual(w.title, "MRR")
        XCTAssertEqual(w.type, .number)
        XCTAssertEqual(w.position, 0)
        XCTAssertEqual(w.anomaly, false)
        XCTAssertNil(w.anomalyExplanation)
        XCTAssertEqual(w.value?.raw, .number(18420))
        XCTAssertEqual(w.value?.numberValue, 18420)
    }

    func testDecodesAnomalyWidget() throws {
        let resp = try JSONDecoder().decode(SnapshotResponse.self, from: snapshotJSON)
        let w = resp.widgets[2]
        XCTAssertEqual(w.id, "w-errors")
        XCTAssertTrue(w.anomaly)
        XCTAssertNotNil(w.anomalyExplanation)
        XCTAssertTrue(w.anomalyExplanation?.contains("tripled") ?? false)
    }

    func testDecodesWidgetWithNullValueAndUnknownType() throws {
        let resp = try JSONDecoder().decode(SnapshotResponse.self, from: snapshotJSON)
        let w = resp.widgets[3]
        XCTAssertEqual(w.type, .unknown, "Unknown server-side type must degrade to .unknown")
        XCTAssertNil(w.value?.raw, "Null value should decode to SnapshotValue with nil raw")
        XCTAssertNil(w.ts)
    }

    func testSnapshotResponseEncodable() throws {
        // Having decoded successfully, re-encoding must not throw. (SnapshotResponse
        // is declared Codable so the compiler-synthesised encoder is exercised here.)
        let resp = try JSONDecoder().decode(SnapshotResponse.self, from: snapshotJSON)
        let encoded = try JSONEncoder().encode(resp)
        XCTAssertGreaterThan(encoded.count, 0)

        // And the round-trip decodes back to an equivalent shape.
        let again = try JSONDecoder().decode(SnapshotResponse.self, from: encoded)
        XCTAssertEqual(again.dashboardId, resp.dashboardId)
        XCTAssertEqual(again.widgets.count, resp.widgets.count)
        XCTAssertEqual(again.widgets[0].value?.numberValue, resp.widgets[0].value?.numberValue)
    }

    func testDecodesWidgetWithHistoryAndInvestigation() throws {
        // Mirrors the new fields the server now sends per widget — sparkline
        // history + the latest investigation pointer for tap-to-investigate.
        let json = """
        {
          "dashboardId": "dash-3",
          "name": "Investigated",
          "themeId": "default",
          "theme": null,
          "widgets": [
            {
              "id": "w-mrr",
              "title": "Stripe MRR",
              "type": "number_with_trend",
              "position": 0,
              "value": 4287.5,
              "anomaly": false,
              "anomalyExplanation": null,
              "ts": "2026-04-26T12:00:00Z",
              "history": [4280, 4281, 4283, 4285, 4287, 4287.5],
              "investigationId": null,
              "investigationStatus": null
            },
            {
              "id": "w-errors",
              "title": "Critical errors (15m)",
              "type": "number",
              "position": 1,
              "value": 47,
              "anomaly": true,
              "anomalyExplanation": "Spike of 47 errors after a sustained zero baseline.",
              "ts": "2026-04-26T12:01:00Z",
              "history": [0, 0, 0, 0, 47],
              "investigationId": "inv-abc-1",
              "investigationStatus": "running"
            }
          ]
        }
        """.data(using: .utf8)!

        let resp = try JSONDecoder().decode(SnapshotResponse.self, from: json)
        XCTAssertEqual(resp.widgets.count, 2)

        let mrr = resp.widgets[0]
        XCTAssertEqual(mrr.history?.count, 6)
        XCTAssertEqual(mrr.history?.last, 4287.5)
        XCTAssertNil(mrr.investigationId)
        XCTAssertNil(mrr.investigationStatus)

        let err = resp.widgets[1]
        XCTAssertTrue(err.anomaly)
        XCTAssertEqual(err.history, [0, 0, 0, 0, 47])
        XCTAssertEqual(err.investigationId, "inv-abc-1")
        XCTAssertEqual(err.investigationStatus, "running")
    }

    func testSnapshotResponseDecodesWithoutOptionalTheme() throws {
        let json = """
        {
          "dashboardId": "dash-2",
          "name": "Minimal",
          "themeId": null,
          "theme": null,
          "widgets": []
        }
        """.data(using: .utf8)!

        let resp = try JSONDecoder().decode(SnapshotResponse.self, from: json)
        XCTAssertEqual(resp.dashboardId, "dash-2")
        XCTAssertNil(resp.themeId)
        XCTAssertNil(resp.theme)
        XCTAssertEqual(resp.widgets.count, 0)
    }
}

final class DashboardListResponseTests: XCTestCase {
    func testDecodesList() throws {
        let json = """
        {
          "dashboards": [
            { "id": "dash-1", "name": "Indie SaaS", "themeId": "default", "createdAt": "2026-04-23T12:00:00Z" },
            { "id": "dash-2", "name": "Ops", "themeId": null, "createdAt": null }
          ]
        }
        """.data(using: .utf8)!

        let resp = try JSONDecoder().decode(DashboardListResponse.self, from: json)
        XCTAssertEqual(resp.dashboards.count, 2)
        XCTAssertEqual(resp.dashboards[0].id, "dash-1")
        XCTAssertEqual(resp.dashboards[0].name, "Indie SaaS")
        XCTAssertEqual(resp.dashboards[0].themeId, "default")
        XCTAssertEqual(resp.dashboards[1].id, "dash-2")
        XCTAssertNil(resp.dashboards[1].themeId)
        XCTAssertNil(resp.dashboards[1].createdAt)
    }

    func testDecodesEmptyList() throws {
        let json = "{ \"dashboards\": [] }".data(using: .utf8)!
        let resp = try JSONDecoder().decode(DashboardListResponse.self, from: json)
        XCTAssertEqual(resp.dashboards.count, 0)
    }
}
