import SwiftUI

/// Renders a single widget card in the app's dashboard detail view.
/// Kept visually close to what the Home Screen / Lock Screen widgets
/// display so the in-app view feels like a larger version of the same thing.
struct WidgetCardView: View {
    let widget: SnapshotWidget
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(widget.title.uppercased())
                    .font(theme.secondaryFont(size: 11))
                    .foregroundStyle(Color(hex: theme.colors.secondary))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if widget.anomaly {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color(hex: theme.colors.negative))
                }
            }
            Spacer(minLength: 4)
            valueBody
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: theme.colors.surface))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(hex: theme.colors.border), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var valueBody: some View {
        switch widget.type {
        case .list:
            listBody
        case .status:
            statusBody
        case .sparkline:
            sparklineBody
        case .number_with_trend:
            numberWithTrendBody
        default:
            numberBody
        }
    }

    private var numberBody: some View {
        Text(widget.value?.displayString ?? "—")
            .font(theme.primaryFont(size: 34))
            .foregroundStyle(Color(hex: theme.colors.primary))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    }

    private var numberWithTrendBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(widget.value?.displayString ?? "—")
                    .font(theme.primaryFont(size: 30))
                    .foregroundStyle(Color(hex: theme.colors.primary))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                TrendBadge(
                    history: widget.history ?? [],
                    positive: Color(hex: theme.colors.positive),
                    negative: Color(hex: theme.colors.negative),
                    neutral: Color(hex: theme.colors.secondary)
                )
            }
            if let history = widget.history, history.count >= 2 {
                Sparkline(
                    values: history,
                    stroke: Color(hex: theme.chart.stroke),
                    fillStart: Color(hex: theme.chart.fillStart),
                    fillEnd: Color(hex: theme.chart.fillEnd)
                )
                .frame(height: 22)
            }
        }
    }

    private var sparklineBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(widget.value?.displayString ?? "—")
                .font(theme.primaryFont(size: 24))
                .foregroundStyle(Color(hex: theme.colors.primary))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            if let history = widget.history, history.count >= 2 {
                Sparkline(
                    values: history,
                    stroke: Color(hex: theme.chart.stroke),
                    fillStart: Color(hex: theme.chart.fillStart),
                    fillEnd: Color(hex: theme.chart.fillEnd)
                )
                .frame(height: 38)
            } else {
                Text("Collecting data…")
                    .font(theme.secondaryFont(size: 11))
                    .foregroundStyle(Color(hex: theme.colors.secondary))
            }
        }
    }

    private var listBody: some View {
        let items = arrayValue(widget.value).prefix(3)
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, value in
                Text(stringifyListItem(value))
                    .font(theme.primaryFont(size: 14))
                    .foregroundStyle(Color(hex: theme.colors.primary))
                    .lineLimit(1)
            }
            if items.isEmpty {
                Text("—").font(theme.primaryFont(size: 20))
                    .foregroundStyle(Color(hex: theme.colors.secondary))
            }
        }
    }

    private var statusBody: some View {
        let raw = widget.value?.raw
        let (label, color) = statusInfo(raw)
        return HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 14, height: 14)
            Text(label)
                .font(theme.primaryFont(size: 20))
                .foregroundStyle(Color(hex: theme.colors.primary))
        }
    }

    private func arrayValue(_ sv: SnapshotValue?) -> [JSONValue] {
        if case let .array(items) = sv?.raw { return items }
        return []
    }

    private func stringifyListItem(_ v: JSONValue) -> String {
        switch v {
        case let .string(s): return s
        case let .number(n): return String(n)
        case let .bool(b): return b ? "true" : "false"
        case let .object(dict):
            // Try common name/label/id keys, then value/count.
            let name = dict["name"] ?? dict["label"] ?? dict["title"] ?? dict["id"]
            let value = dict["value"] ?? dict["count"] ?? dict["total"]
            if let name = flatten(name), let value = flatten(value) {
                return "\(name) · \(value)"
            }
            return flatten(name) ?? flatten(value) ?? "\(dict.count) keys"
        case let .array(a): return "[\(a.count)]"
        case .null: return "null"
        }
    }

    private func flatten(_ v: JSONValue?) -> String? {
        switch v {
        case let .string(s): return s
        case let .number(n):
            if n.truncatingRemainder(dividingBy: 1) == 0 { return String(Int64(n)) }
            return String(format: "%.2f", n)
        case let .bool(b): return b ? "true" : "false"
        default: return nil
        }
    }

    private func statusInfo(_ v: JSONValue?) -> (String, Color) {
        switch v {
        case let .string(s):
            let lowered = s.lowercased()
            if ["ok", "up", "healthy", "good", "green"].contains(lowered) {
                return (s, Color(hex: theme.colors.positive))
            }
            if ["warn", "warning", "degraded", "yellow"].contains(lowered) {
                return (s, Color(hex: theme.colors.accent))
            }
            if ["error", "down", "bad", "red", "critical", "fail", "failed"].contains(lowered) {
                return (s, Color(hex: theme.colors.negative))
            }
            return (s, Color(hex: theme.colors.primary))
        case let .bool(b):
            return b
                ? ("OK", Color(hex: theme.colors.positive))
                : ("DOWN", Color(hex: theme.colors.negative))
        case let .number(n):
            return n == 0
                ? ("ZERO", Color(hex: theme.colors.positive))
                : ("\(n)", Color(hex: theme.colors.accent))
        default:
            return ("—", Color(hex: theme.colors.secondary))
        }
    }
}
