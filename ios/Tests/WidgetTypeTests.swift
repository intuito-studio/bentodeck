import XCTest
@testable import BentoDeck

final class WidgetTypeTests: XCTestCase {

    private func decodeType(_ raw: String) throws -> WidgetType {
        // WidgetType decodes from a single string value.
        let data = "\"\(raw)\"".data(using: .utf8)!
        return try JSONDecoder().decode(WidgetType.self, from: data)
    }

    func testDecodesNumber() throws {
        XCTAssertEqual(try decodeType("number"), .number)
    }

    func testDecodesNumberWithTrend() throws {
        XCTAssertEqual(try decodeType("number_with_trend"), .number_with_trend)
    }

    func testDecodesGauge() throws {
        XCTAssertEqual(try decodeType("gauge"), .gauge)
    }

    func testDecodesSparkline() throws {
        XCTAssertEqual(try decodeType("sparkline"), .sparkline)
    }

    func testDecodesList() throws {
        XCTAssertEqual(try decodeType("list"), .list)
    }

    func testDecodesStatus() throws {
        XCTAssertEqual(try decodeType("status"), .status)
    }

    func testUnknownStringDecodesToUnknownNotThrow() throws {
        let type = try decodeType("heatmap_that_server_will_add_someday")
        XCTAssertEqual(type, .unknown)
    }

    func testEmptyStringDecodesToUnknown() throws {
        let type = try decodeType("")
        XCTAssertEqual(type, .unknown)
    }
}
