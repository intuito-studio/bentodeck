import XCTest
@testable import BentoDeck

final class JSONValueTests: XCTestCase {

    private func roundtrip(_ v: JSONValue) throws -> JSONValue {
        let data = try JSONEncoder().encode(v)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    func testStringRoundtrip() throws {
        let v = JSONValue.string("hello")
        XCTAssertEqual(try roundtrip(v), v)
    }

    func testNumberRoundtripInteger() throws {
        let v = JSONValue.number(42)
        XCTAssertEqual(try roundtrip(v), v)
    }

    func testNumberRoundtripFloat() throws {
        let v = JSONValue.number(3.14159)
        XCTAssertEqual(try roundtrip(v), v)
    }

    func testBoolRoundtripTrue() throws {
        let v = JSONValue.bool(true)
        XCTAssertEqual(try roundtrip(v), v)
    }

    func testBoolRoundtripFalse() throws {
        let v = JSONValue.bool(false)
        XCTAssertEqual(try roundtrip(v), v)
    }

    func testNullRoundtrip() throws {
        let v = JSONValue.null
        XCTAssertEqual(try roundtrip(v), v)
    }

    func testArrayRoundtrip() throws {
        let v = JSONValue.array([
            .string("a"),
            .number(1),
            .bool(false),
            .null,
        ])
        XCTAssertEqual(try roundtrip(v), v)
    }

    func testNestedObjectRoundtrip() throws {
        let v = JSONValue.object([
            "name": .string("BentoDeck"),
            "active": .bool(true),
            "count": .number(7),
            "tags": .array([.string("mcp"), .string("widget")]),
            "meta": .object([
                "nested": .bool(true),
                "level": .number(2),
            ]),
        ])
        XCTAssertEqual(try roundtrip(v), v)
    }

    // Decode-order priority: bool must be tried before number. Swift's
    // JSONDecoder will happily decode `true` as `1.0` if you ask for a Double,
    // so the custom init(from:) must test Bool first to preserve the bool case.
    func testDecodeOrderPrioritizesBoolOverNumber() throws {
        let trueData = "true".data(using: .utf8)!
        let falseData = "false".data(using: .utf8)!
        let v1 = try JSONDecoder().decode(JSONValue.self, from: trueData)
        let v2 = try JSONDecoder().decode(JSONValue.self, from: falseData)
        guard case .bool(let b1) = v1 else {
            return XCTFail("Expected .bool case, got \(v1)")
        }
        guard case .bool(let b2) = v2 else {
            return XCTFail("Expected .bool case, got \(v2)")
        }
        XCTAssertTrue(b1)
        XCTAssertFalse(b2)
    }

    func testDecodeNumber() throws {
        let data = "42.5".data(using: .utf8)!
        let v = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case .number(let n) = v else {
            return XCTFail("Expected .number, got \(v)")
        }
        XCTAssertEqual(n, 42.5, accuracy: 0.0001)
    }

    func testDecodeString() throws {
        let data = "\"hi\"".data(using: .utf8)!
        let v = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case .string(let s) = v else {
            return XCTFail("Expected .string, got \(v)")
        }
        XCTAssertEqual(s, "hi")
    }

    func testDecodeNullFromJSONNull() throws {
        let data = "null".data(using: .utf8)!
        let v = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(v, .null)
    }

    func testDecodeMixedArrayFromJSON() throws {
        let data = "[1, \"two\", true, null]".data(using: .utf8)!
        let v = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case .array(let items) = v else {
            return XCTFail("Expected .array, got \(v)")
        }
        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(items[0], .number(1))
        XCTAssertEqual(items[1], .string("two"))
        XCTAssertEqual(items[2], .bool(true))
        XCTAssertEqual(items[3], .null)
    }
}
