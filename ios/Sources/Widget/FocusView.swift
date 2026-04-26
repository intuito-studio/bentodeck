import SwiftUI
import WidgetKit

/// Renders ONE widget richly, taking up the entire home-screen widget surface.
/// Used by the focus widget (smart pick + user-configurable variants).
///
/// Adapts content density to `widgetFamily` — small shows a single hero
/// metric, medium adds a sparkline, large goes full-rich (sparkline +
/// recent values + min/max), extra-large stretches everything wider.
struct FocusView: View {
    let widget: SnapshotWidget?
    let theme: Theme
    let lastRefreshedAt: Date?
    var useGlass: Bool = false
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let widget {
                content(widget: widget)
            } else {
                placeholder
            }
        }
        .padding(useGlass ? 14 : 0)
        .background(
            // Wrap the focus content in a glass surface when there's a
            // background image — the whole tile gets the same liquid-glass
            // treatment as the in-app cards.
            Group {
                if useGlass {
                    GlassSurface(
                        useGlass: true,
                        surfaceColor: Color(hex: theme.colors.surface),
                        borderColor: Color(hex: theme.colors.border),
                        cornerRadius: 22
                    )
                }
            }
        )
    }

    // MARK: - Layout

    @ViewBuilder
    private func content(widget: SnapshotWidget) -> some View {
        let scale = FocusScale(family: family)
        VStack(alignment: .leading, spacing: scale.headerSpacing) {
            header(widget: widget, scale: scale)
            Spacer(minLength: 0)
            valueBlock(widget: widget, scale: scale)
            if scale.showsSparklineRow,
               let history = widget.history, history.count >= 2,
               supportsSparkline(widget) {
                Spacer(minLength: 4)
                Sparkline(
                    values: history,
                    stroke: Color(hex: theme.chart.stroke),
                    fillStart: Color(hex: theme.chart.fillStart),
                    fillEnd: Color(hex: theme.chart.fillEnd),
                    lineWidth: scale.sparklineLineWidth
                )
                .frame(height: scale.sparklineHeight)
            }
            if scale.showsExtras {
                Spacer(minLength: 6)
                extrasBlock(widget: widget, scale: scale)
            }
            Spacer(minLength: 0)
            footer(widget: widget, scale: scale)
        }
    }

    private func header(widget: SnapshotWidget, scale: FocusScale) -> some View {
        HStack(spacing: 6) {
            Text(widget.title.uppercased())
                .font(theme.secondaryFont(size: scale.titleSize))
                .foregroundStyle(Color(hex: theme.colors.secondary))
                .lineLimit(1)
            Spacer(minLength: 0)
            if widget.anomaly {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: scale.anomalyIconSize, weight: .semibold))
                    .foregroundStyle(Color(hex: theme.colors.negative))
            }
        }
    }

    @ViewBuilder
    private func valueBlock(widget: SnapshotWidget, scale: FocusScale) -> some View {
        switch widget.type {
        case .list:
            listBody(widget: widget, scale: scale)
        case .status:
            statusBody(widget: widget, scale: scale)
        default:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(widget.value?.displayString ?? "—")
                    .font(theme.primaryFont(size: scale.valueSize))
                    .foregroundStyle(Color(hex: theme.colors.primary))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                TrendBadge(
                    history: widget.history ?? [],
                    positive: Color(hex: theme.colors.positive),
                    negative: Color(hex: theme.colors.negative),
                    neutral: Color(hex: theme.colors.secondary),
                    font: .system(size: scale.trendSize, weight: .semibold)
                )
                Spacer(minLength: 0)
            }
        }
    }

    private func listBody(widget: SnapshotWidget, scale: FocusScale) -> some View {
        let items = arrayValue(widget.value).prefix(scale.maxListItems)
        return VStack(alignment: .leading, spacing: scale.listRowSpacing) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, value in
                Text(stringifyListItem(value))
                    .font(theme.primaryFont(size: scale.listFontSize))
                    .foregroundStyle(Color(hex: theme.colors.primary))
                    .lineLimit(1)
            }
            if items.isEmpty {
                Text("—")
                    .font(theme.primaryFont(size: scale.valueSize))
                    .foregroundStyle(Color(hex: theme.colors.secondary))
            }
        }
    }

    private func statusBody(widget: SnapshotWidget, scale: FocusScale) -> some View {
        let (label, color) = statusInfo(widget.value?.raw)
        return HStack(spacing: scale.statusSpacing) {
            Circle()
                .fill(color)
                .frame(width: scale.statusDot, height: scale.statusDot)
            Text(label)
                .font(theme.primaryFont(size: scale.valueSize))
                .foregroundStyle(Color(hex: theme.colors.primary))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func extrasBlock(widget: SnapshotWidget, scale: FocusScale) -> some View {
        // At large+ sizes there's room for a min/max strip from the history.
        // Anomaly explanation, when present, takes priority over the strip
        // since it's the most actionable thing to surface.
        if widget.anomaly, let explanation = widget.anomalyExplanation {
            Text(explanation)
                .font(theme.secondaryFont(size: scale.extrasSize))
                .foregroundStyle(Color(hex: theme.colors.secondary))
                .lineLimit(scale.extrasLineLimit)
        } else if let history = widget.history, history.count >= 2 {
            HStack(spacing: 16) {
                statBox(label: "MIN", value: formatHistoryValue(history.min()), scale: scale)
                statBox(label: "MAX", value: formatHistoryValue(history.max()), scale: scale)
                statBox(label: "POINTS", value: "\(history.count)", scale: scale)
                Spacer(minLength: 0)
            }
        }
    }

    private func statBox(label: String, value: String, scale: FocusScale) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(theme.secondaryFont(size: scale.extrasSize - 2))
                .foregroundStyle(Color(hex: theme.colors.secondary))
            Text(value)
                .font(theme.primaryFont(size: scale.extrasSize + 2))
                .foregroundStyle(Color(hex: theme.colors.primary))
        }
    }

    @ViewBuilder
    private func footer(widget: SnapshotWidget, scale: FocusScale) -> some View {
        if scale.showsFooter, let ts = widget.ts ?? formattedRefreshedAt() {
            Text(ts)
                .font(theme.secondaryFont(size: scale.footerSize))
                .foregroundStyle(Color(hex: theme.colors.secondary))
                .lineLimit(1)
        }
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar.doc.horizontal")
                .foregroundStyle(.secondary)
            Text("Open BentoDeck and pick a dashboard")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func supportsSparkline(_ widget: SnapshotWidget) -> Bool {
        switch widget.type {
        case .number, .number_with_trend, .sparkline, .gauge:
            return true
        case .list, .status, .unknown:
            return false
        }
    }

    private func formatHistoryValue(_ v: Double?) -> String {
        guard let v else { return "—" }
        if v.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int64(v))
        }
        return String(format: "%.2f", v)
    }

    private func formattedRefreshedAt() -> String? {
        guard let lastRefreshedAt else { return nil }
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return "Updated \(f.string(from: lastRefreshedAt))"
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

/// Per-family rendering knobs. Bigger families render bigger fonts, more
/// list rows, the min/max/points strip, and a footer line.
private struct FocusScale {
    let titleSize: CGFloat
    let valueSize: CGFloat
    let trendSize: CGFloat
    let sparklineHeight: CGFloat
    let sparklineLineWidth: CGFloat
    let listFontSize: CGFloat
    let listRowSpacing: CGFloat
    let maxListItems: Int
    let statusDot: CGFloat
    let statusSpacing: CGFloat
    let anomalyIconSize: CGFloat
    let extrasSize: CGFloat
    let extrasLineLimit: Int
    let footerSize: CGFloat
    let headerSpacing: CGFloat
    let showsSparklineRow: Bool
    let showsExtras: Bool
    let showsFooter: Bool

    init(family: WidgetFamily) {
        switch family {
        case .systemSmall:
            self.titleSize = 10
            self.valueSize = 38
            self.trendSize = 10
            self.sparklineHeight = 22
            self.sparklineLineWidth = 1.5
            self.listFontSize = 12
            self.listRowSpacing = 2
            self.maxListItems = 3
            self.statusDot = 14
            self.statusSpacing = 8
            self.anomalyIconSize = 11
            self.extrasSize = 10
            self.extrasLineLimit = 2
            self.footerSize = 9
            self.headerSpacing = 4
            self.showsSparklineRow = true
            self.showsExtras = false
            self.showsFooter = false

        case .systemMedium:
            self.titleSize = 12
            self.valueSize = 56
            self.trendSize = 13
            self.sparklineHeight = 38
            self.sparklineLineWidth = 1.8
            self.listFontSize = 16
            self.listRowSpacing = 4
            self.maxListItems = 4
            self.statusDot = 22
            self.statusSpacing = 12
            self.anomalyIconSize = 14
            self.extrasSize = 11
            self.extrasLineLimit = 2
            self.footerSize = 10
            self.headerSpacing = 6
            self.showsSparklineRow = true
            self.showsExtras = false
            self.showsFooter = true

        case .systemLarge:
            self.titleSize = 14
            self.valueSize = 88
            self.trendSize = 16
            self.sparklineHeight = 80
            self.sparklineLineWidth = 2.2
            self.listFontSize = 18
            self.listRowSpacing = 8
            self.maxListItems = 8
            self.statusDot = 30
            self.statusSpacing = 16
            self.anomalyIconSize = 18
            self.extrasSize = 12
            self.extrasLineLimit = 3
            self.footerSize = 11
            self.headerSpacing = 10
            self.showsSparklineRow = true
            self.showsExtras = true
            self.showsFooter = true

        case .systemExtraLarge:
            self.titleSize = 16
            self.valueSize = 110
            self.trendSize = 18
            self.sparklineHeight = 90
            self.sparklineLineWidth = 2.5
            self.listFontSize = 20
            self.listRowSpacing = 10
            self.maxListItems = 12
            self.statusDot = 36
            self.statusSpacing = 18
            self.anomalyIconSize = 20
            self.extrasSize = 14
            self.extrasLineLimit = 3
            self.footerSize = 12
            self.headerSpacing = 12
            self.showsSparklineRow = true
            self.showsExtras = true
            self.showsFooter = true

        default:
            self.titleSize = 12
            self.valueSize = 56
            self.trendSize = 13
            self.sparklineHeight = 38
            self.sparklineLineWidth = 1.8
            self.listFontSize = 16
            self.listRowSpacing = 4
            self.maxListItems = 4
            self.statusDot = 22
            self.statusSpacing = 12
            self.anomalyIconSize = 14
            self.extrasSize = 11
            self.extrasLineLimit = 2
            self.footerSize = 10
            self.headerSpacing = 6
            self.showsSparklineRow = true
            self.showsExtras = false
            self.showsFooter = false
        }
    }
}
