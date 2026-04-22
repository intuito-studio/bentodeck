import XCTest
@testable import BentoDeck

final class SnapshotValueTests: XCTestCase {

    // MARK: - displayString

    func testDisplayStringIntegerLookingNumber() {
        let v = SnapshotValue(raw: .number(1234))
        // Formatter output is locale-dependent; assert it contains the digits.
        let s = v.displayString
        XCTAssertTrue(s.contains("1") && s.contains("234"),
                      "Integer-looking number should be formatted with grouping, got: \(s)")
        XCTAssertFalse(s.contains("."),
                       "Integer-looking number must not render a decimal point, got: \(s)")
    }

    func testDisplayStringFloatNumber() {
        let v = SnapshotValue(raw: .number(12.5))
        XCTAssertEqual(v.displayString, "12.50")
    }

    func testDisplayStringFloatNumberRoundsToTwoDecimals() {
        let v = SnapshotValue(raw: .number(3.14159))
        XCTAssertEqual(v.displayString, "3.14")
    }

    func testDisplayStringZero() {
        let v = SnapshotValue(raw: .number(0))
        XCTAssertEqual(v.displayString, "0")
    }

    func testDisplayStringNegativeInteger() {
        let v = SnapshotValue(raw: .number(-7))
        XCTAssertEqual(v.displayString, "-7")
    }

    func testDisplayStringString() {
        let v = SnapshotValue(raw: .string("ok"))
        XCTAssertEqual(v.displayString, "ok")
    }

    func testDisplayStringBoolTrue() {
        let v = SnapshotValue(raw: .bool(true))
        XCTAssertEqual(v.displayString, "true")
    }

    func testDisplayStringBoolFalse() {
        let v = SnapshotValue(raw: .bool(false))
        XCTAssertEqual(v.displayString, "false")
    }

    func testDisplayStringArraySaysNItems() {
        let v = SnapshotValue(raw: .array([.string("a"), .string("b"), .string("c")]))
        XCTAssertEqual(v.displayString, "3 items")
    }

    func testDisplayStringEmptyArray() {
        let v = SnapshotValue(raw: .array([]))
        XCTAssertEqual(v.displayString, "0 items")
    }

    func testDisplayStringObjectSaysNKeys() {
        let v = SnapshotValue(raw: .object(["a": .number(1), "b": .number(2)]))
        XCTAssertEqual(v.displayString, "2 keys")
    }

    func testDisplayStringNull() {
        let v = SnapshotValue(raw: .null)
        XCTAssertEqual(v.displayString, "—")
    }

    func testDisplayStringAbsent() {
        let v = SnapshotValue(raw: nil)
        XCTAssertEqual(v.displayString, "—")
    }

    // MARK: - numberValue coercion

    func testNumberValueFromNumber() {
        let v = SnapshotValue(raw: .number(42.5))
        XCTAssertEqual(v.numberValue, 42.5)
    }

    func testNumberValueFromNumericString() {
        let v = SnapshotValue(raw: .string("99.9"))
        XCTAssertEqual(v.numberValue, 99.9)
    }

    func testNumberValueFromNonNumericStringIsNil() {
        let v = SnapshotValue(raw: .string("not a number"))
        XCTAssertNil(v.numberValue)
    }

    func testNumberValueFromBoolTrueIsOne() {
        let v = SnapshotValue(raw: .bool(true))
        XCTAssertEqual(v.numberValue, 1)
    }

    func testNumberValueFromBoolFalseIsZero() {
        let v = SnapshotValue(raw: .bool(false))
        XCTAssertEqual(v.numberValue, 0)
    }

    func testNumberValueFromArrayIsNil() {
        let v = SnapshotValue(raw: .array([.number(1), .number(2)]))
        XCTAssertNil(v.numberValue)
    }

    func testNumberValueFromObjectIsNil() {
        let v = SnapshotValue(raw: .object(["a": .number(1)]))
        XCTAssertNil(v.numberValue)
    }

    func testNumberValueFromNullIsNil() {
        let v = SnapshotValue(raw: .null)
        XCTAssertNil(v.numberValue)
    }

    func testNumberValueFromAbsentIsNil() {
        let v = SnapshotValue(raw: nil)
        XCTAssertNil(v.numberValue)
    }

    // MARK: - Codable

    func testSnapshotValueCodableRoundtripNumber() throws {
        let original = SnapshotValue(raw: .number(42))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SnapshotValue.self, from: data)
        XCTAssertEqual(decoded.raw, .number(42))
    }

    func testSnapshotValueCodableRoundtripNull() throws {
        let original = SnapshotValue(raw: nil)
        let data = try JSONEncoder().encode(original)
        // encoded representation should be `null`
        XCTAssertEqual(String(data: data, encoding: .utf8), "null")
        let decoded = try JSONDecoder().decode(SnapshotValue.self, from: data)
        XCTAssertNil(decoded.raw)
    }

    func testSnapshotValueDecodesRawNullToNilRaw() throws {
        let data = "null".data(using: .utf8)!
        let v = try JSONDecoder().decode(SnapshotValue.self, from: data)
        XCTAssertNil(v.raw)
        XCTAssertEqual(v.displayString, "—")
    }
}
