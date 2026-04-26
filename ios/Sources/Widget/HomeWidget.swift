import SwiftUI
import WidgetKit

struct HomeWidget: Widget {
    let kind = "HomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BentoTimelineProvider()) { entry in
            HomeWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(hex: entry.theme.colors.background)
                }
        }
        .configurationDisplayName("BentoDeck")
        .description("Live dashboards from Claude, on your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct HomeWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: BentoEntry

    var body: some View {
        switch family {
        case .systemSmall: smallView
        case .systemMedium: mediumView
        default: smallView
        }
    }

    private var smallView: some View {
        let widget = entry.snapshot?.widgets.first
        let history = widget?.history ?? []
        let showSparkline =
            history.count >= 2
            && (widget?.type == .sparkline || widget?.type == .number_with_trend)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(widget?.title.uppercased() ?? "BENTO")
                    .font(entry.theme.secondaryFont(size: 10))
                    .foregroundStyle(Color(hex: entry.theme.colors.secondary))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if widget?.anomaly == true {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color(hex: entry.theme.colors.negative))
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(widget?.value?.displayString ?? "—")
                    .font(entry.theme.primaryFont(size: showSparkline ? 28 : 40))
                    .foregroundStyle(Color(hex: entry.theme.colors.primary))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                TrendBadge(
                    history: history,
                    positive: Color(hex: entry.theme.colors.positive),
                    negative: Color(hex: entry.theme.colors.negative),
                    neutral: Color(hex: entry.theme.colors.secondary),
                    font: .system(size: 9, weight: .semibold)
                )
            }
            if showSparkline {
                Sparkline(
                    values: history,
                    stroke: Color(hex: entry.theme.chart.stroke),
                    fillStart: Color(hex: entry.theme.chart.fillStart),
                    fillEnd: Color(hex: entry.theme.chart.fillEnd)
                )
                .frame(height: 22)
            }
            Spacer(minLength: 0)
            if let ts = widget?.ts {
                Text(ts)
                    .font(entry.theme.secondaryFont(size: 9))
                    .foregroundStyle(Color(hex: entry.theme.colors.secondary))
                    .lineLimit(1)
            }
        }
    }

    private var mediumView: some View {
        let widgets = (entry.snapshot?.widgets ?? []).prefix(4)
        return Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                tile(widgets.indices.contains(0) ? Array(widgets)[0] : nil)
                tile(widgets.indices.contains(1) ? Array(widgets)[1] : nil)
            }
            GridRow {
                tile(widgets.indices.contains(2) ? Array(widgets)[2] : nil)
                tile(widgets.indices.contains(3) ? Array(widgets)[3] : nil)
            }
        }
    }

    @ViewBuilder
    private func tile(_ widget: SnapshotWidget?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(widget?.title.uppercased() ?? "—")
                    .font(entry.theme.secondaryFont(size: 9))
                    .foregroundStyle(Color(hex: entry.theme.colors.secondary))
                    .lineLimit(1)
                if widget?.anomaly == true {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(hex: entry.theme.colors.negative))
                }
            }
            Text(widget?.value?.displayString ?? "—")
                .font(entry.theme.primaryFont(size: 22))
                .foregroundStyle(Color(hex: entry.theme.colors.primary))
                .minimumScaleFactor(0.4)
                .lineLimit(1)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: entry.theme.colors.surface))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(hex: entry.theme.colors.border), lineWidth: 0.5)
                )
        )
    }
}
