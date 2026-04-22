import Foundation

/// The shape the iOS app + widget receive from the backend's
/// /dashboards endpoints. These mirror the server's HTTP response bodies
/// exactly; `Optional` wraps any field the server may omit.

struct DashboardSummary: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let themeId: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, themeId = "themeId", createdAt = "createdAt"
        // Server returns themeId already camelCased thanks to repo mapping,
        // but include a tolerant decoder path below just in case.
    }
}

struct DashboardListResponse: Codable {
    let dashboards: [DashboardSummary]
}

struct SnapshotWidget: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let type: WidgetType
    let position: Int
    let value: SnapshotValue?
    let anomaly: Bool
    let anomalyExplanation: String?
    let ts: String?
}

/// Widget type enum that is string-tolerant — if the server adds a new type
/// later, we degrade gracefully to `.unknown` instead of crashing.
enum WidgetType: String, Codable {
    case number
    case number_with_trend
    case gauge
    case sparkline
    case list
    case status
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WidgetType(rawValue: raw) ?? .unknown
    }
}

/// A widget's value can be almost anything. This wrapper decodes JSON
/// primitives + arrays + dictionaries without losing structure, and
/// provides convenience accessors the views use.
struct SnapshotValue: Codable, Hashable {
    let raw: JSONValue?

    init(raw: JSONValue?) { self.raw = raw }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.raw = nil
        } else {
            self.raw = try container.decode(JSONValue.self)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let raw { try container.encode(raw) } else { try container.encodeNil() }
    }

    var numberValue: Double? {
        switch raw {
        case let .number(n): return n
        case let .string(s): return Double(s)
        case let .bool(b): return b ? 1 : 0
        default: return nil
        }
    }

    var displayString: String {
        switch raw {
        case let .number(n):
            if n.truncatingRemainder(dividingBy: 1) == 0 {
                return formatted(Int64(n))
            }
            return String(format: "%.2f", n)
        case let .string(s): return s
        case let .bool(b): return b ? "true" : "false"
        case let .array(items): return "\(items.count) items"
        case let .object(dict): return "\(dict.count) keys"
        case .none, .null: return "—"
        }
    }

    private func formatted(_ n: Int64) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }
}

/// A minimal JSON value type, good enough to round-trip whatever the
/// server produces.
enum JSONValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(
            in: c, debugDescription: "unrecognized JSON value"
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case let .bool(v): try c.encode(v)
        case let .number(v): try c.encode(v)
        case let .string(v): try c.encode(v)
        case let .array(v): try c.encode(v)
        case let .object(v): try c.encode(v)
        }
    }
}

struct SnapshotResponse: Codable {
    let dashboardId: String
    let name: String
    let themeId: String?
    let theme: Theme?
    let widgets: [SnapshotWidget]
}
