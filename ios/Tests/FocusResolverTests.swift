import XCTest
@testable import BentoDeck

final class FocusSmartPickTests: XCTestCase {
    private func widget(
        id: String,
        position: Int = 0,
        anomaly: Bool = false,
        ts: String? = nil
    ) -> SnapshotWidget {
        SnapshotWidget(
            id: id,
            title: id,
            type: .number,
            position: position,
            value: SnapshotValue(raw: .number(0)),
            anomaly: anomaly,
            anomalyExplanation: nil,
            ts: ts,
            history: nil,
            investigationId: nil,
            investigationStatus: nil,
            sourceId: nil,
            sourceName: nil,
            needsKey: nil
        )
    }

    func testEmptyArrayReturnsNil() {
        XCTAssertNil(FocusSmartPick.pick(from: []))
    }

    func testAnomalyBeatsRecency() {
        // a: anomaly + older ts. b: no anomaly, newest ts.
        let a = widget(id: "a", position: 1, anomaly: true,  ts: "2026-04-26T10:00:00Z")
        let b = widget(id: "b", position: 0, anomaly: false, ts: "2026-04-26T11:00:00Z")
        let pick = FocusSmartPick.pick(from: [b, a])
        XCTAssertEqual(pick?.id, "a", "Anomaly must win over a newer non-anomalous widget")
    }

    func testMostRecentTsWinsWhenNoAnomaly() {
        let a = widget(id: "a", ts: "2026-04-26T10:00:00Z")
        let b = widget(id: "b", ts: "2026-04-26T11:00:00Z")
        let c = widget(id: "c", ts: "2026-04-26T09:00:00Z")
        let pick = FocusSmartPick.pick(from: [a, b, c])
        XCTAssertEqual(pick?.id, "b")
    }

    func testWidgetWithTsBeatsWidgetWithoutTs() {
        let a = widget(id: "a", ts: nil)
        let b = widget(id: "b", ts: "2026-04-26T10:00:00Z")
        let pick = FocusSmartPick.pick(from: [a, b])
        XCTAssertEqual(pick?.id, "b")
    }

    func testFallsBackToPositionZeroWhenAllElseEqual() {
        let a = widget(id: "a", position: 5, ts: nil)
        let b = widget(id: "b", position: 0, ts: nil)
        let c = widget(id: "c", position: 9, ts: nil)
        let pick = FocusSmartPick.pick(from: [a, b, c])
        XCTAssertEqual(pick?.id, "b")
    }

    func testFirstAnomalyWinsWhenMultipleAnomalies() {
        // Order matters — `first(where:)` should pick the first one we
        // encounter, which preserves the dashboard's intended priority.
        let a = widget(id: "a", anomaly: true)
        let b = widget(id: "b", anomaly: true)
        let pick = FocusSmartPick.pick(from: [a, b])
        XCTAssertEqual(pick?.id, "a")
    }
}
