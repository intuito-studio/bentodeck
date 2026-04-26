import SwiftUI

/// Display size class for the in-app dashboard card. Derived from `LayoutSize`
/// — small cells render `.compact`, anything bigger renders `.hero` so the
/// extra real estate isn't wasted.
enum WidgetDisplaySize {
    case compact
    case hero

    init(_ size: LayoutSize) {
        self = size == .small ? .compact : .hero
    }
}

/// Renders a single widget card in the app's dashboard detail view.
/// Kept visually close to what the Home Screen / Lock Screen widgets
/// display so the in-app view feels like a larger version of the same thing.
struct WidgetCardView: View {
    let widget: SnapshotWidget
    let theme: Theme
    var displaySize: WidgetDisplaySize = .compact
    var useGlass: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            HStack {
                Text(widget.title.uppercased())
                    .font(theme.secondaryFont(size: titleFontSize))
                    .foregroundStyle(Color(hex: theme.colors.secondary))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if widget.anomaly {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(displaySize == .hero ? .title3 : .caption)
                        .foregroundStyle(Color(hex: theme.colors.negative))
                }
            }
            Spacer(minLength: 4)
            valueBody
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(displaySize == .hero ? 20 : 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            GlassSurface(
                useGlass: useGlass,
                surfaceColor: Color(hex: theme.colors.surface),
                borderColor: Color(hex: theme.colors.border)
            )
        )
    }

    @ViewBuilder
    private var valueBody: some View {
        // When the underlying source is waiting on an API key, hide the
        // normal value body entirely and show a "Connect" warning. The
        // dashboard's onTap handler is wired (in BentoCell + the home-screen
        // widget) to open the key-entry sheet for `widget.sourceId`.
        if widget.needsKey == true {
            needsKeyBody
        } else {
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
    }

    private var needsKeyBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: displaySize == .hero ? 20 : 14, weight: .semibold))
                    .foregroundStyle(Color(hex: theme.colors.accent))
                Text("Connect")
                    .font(theme.primaryFont(size: displaySize == .hero ? 24 : 18))
                    .foregroundStyle(Color(hex: theme.colors.primary))
            }
            Text(widget.sourceName ?? "this source")
                .font(theme.secondaryFont(size: displaySize == .hero ? 13 : 11))
                .foregroundStyle(Color(hex: theme.colors.secondary))
                .lineLimit(1)
            Text("Tap to add API key")
                .font(theme.secondaryFont(size: displaySize == .hero ? 11 : 10))
                .foregroundStyle(Color(hex: theme.colors.accent))
        }
    }

    private var numberBody: some View {
        Text(widget.value?.displayString ?? "—")
            .font(theme.primaryFont(size: numberFontSize))
            .foregroundStyle(Color(hex: theme.colors.primary))
            .minimumScaleFactor(0.4)
            .lineLimit(1)
    }

    private var numberWithTrendBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(widget.value?.displayString ?? "—")
                    .font(theme.primaryFont(size: numberWithTrendFontSize))
                    .foregroundStyle(Color(hex: theme.colors.primary))
                    .minimumScaleFactor(0.4)
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
                .frame(height: sparklineTrendHeight)
            }
        }
    }

    private var sparklineBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(widget.value?.displayString ?? "—")
                .font(theme.primaryFont(size: sparklineNumberFontSize))
                .foregroundStyle(Color(hex: theme.colors.primary))
                .minimumScaleFactor(0.4)
                .lineLimit(1)
            if let history = widget.history, history.count >= 2 {
                Sparkline(
                    values: history,
                    stroke: Color(hex: theme.chart.stroke),
                    fillStart: Color(hex: theme.chart.fillStart),
                    fillEnd: Color(hex: theme.chart.fillEnd)
                )
                .frame(height: sparklineHeight)
            } else {
                Text("Collecting data…")
                    .font(theme.secondaryFont(size: 11))
                    .foregroundStyle(Color(hex: theme.colors.secondary))
            }
        }
    }

    private var listBody: some View {
        let items = arrayValue(widget.value).prefix(maxListItems)
        return VStack(alignment: .leading, spacing: displaySize == .hero ? 8 : 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, value in
                Text(stringifyListItem(value))
                    .font(theme.primaryFont(size: listFontSize))
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
        return HStack(spacing: displaySize == .hero ? 16 : 10) {
            Circle()
                .fill(color)
                .frame(width: statusDotSize, height: statusDotSize)
            Text(label)
                .font(theme.primaryFont(size: statusFontSize))
                .foregroundStyle(Color(hex: theme.colors.primary))
        }
    }

    // MARK: - Size-driven dimensions

    private var spacing: CGFloat { displaySize == .hero ? 12 : 8 }
    private var titleFontSize: CGFloat { 11 }
    private var numberFontSize: CGFloat { displaySize == .hero ? 64 : 34 }
    private var numberWithTrendFontSize: CGFloat { displaySize == .hero ? 56 : 30 }
    private var sparklineNumberFontSize: CGFloat { displaySize == .hero ? 44 : 24 }
    private var sparklineHeight: CGFloat { displaySize == .hero ? 80 : 38 }
    private var sparklineTrendHeight: CGFloat { displaySize == .hero ? 56 : 22 }
    private var listFontSize: CGFloat { displaySize == .hero ? 18 : 14 }
    private var maxListItems: Int { displaySize == .hero ? 8 : 3 }
    private var statusDotSize: CGFloat { displaySize == .hero ? 24 : 14 }
    private var statusFontSize: CGFloat { displaySize == .hero ? 36 : 20 }

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
