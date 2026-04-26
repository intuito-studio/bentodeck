import SwiftUI
import WidgetKit

struct HomeWidget: Widget {
    let kind = "HomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BentoTimelineProvider()) { entry in
            HomeWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetBackground(entry: entry)
                }
                .widgetURL(deepLink(for: entry))
        }
        .configurationDisplayName("BentoDeck")
        .description("Live dashboards from Claude, on your Home Screen.")
        // Small = 1 hero number; medium = 4-tile 2×2; large = 6-tile 2×3;
        // extra-large (iPad) = 8-tile 4×2. Adding the bigger families lets
        // users put more of the dashboard on the home screen at once.
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }

    private func deepLink(for entry: BentoEntry) -> URL? {
        // WidgetKit only supports one widgetURL per tile, so we pick the
        // most-actionable target. Priority:
        //   1. A widget in "needs key" state → open the API-key sheet for
        //      that source so a tap connects, rather than landing on a
        //      dashboard full of "Connect" cards.
        //   2. Otherwise, fall back to the dashboard.
        if let needsKey = entry.snapshot?.widgets.first(where: { $0.needsKey == true }),
           let sourceId = needsKey.sourceId {
            return BentoDeckLink.dataSourceKey(
                sourceId: sourceId,
                sourceName: needsKey.sourceName
            )
        }
        guard let id = entry.snapshot?.dashboardId else { return nil }
        return BentoDeckLink.dashboard(id: id)
    }
}

struct HomeWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: BentoEntry

    var body: some View {
        switch family {
        case .systemSmall: smallView
        case .systemMedium: mediumView
        case .systemLarge: largeView
        case .systemExtraLarge: extraLargeView
        default: smallView
        }
    }

    // MARK: - Small (1 hero metric)

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

    // MARK: - Medium (4 tiles, 2×2)

    private var mediumView: some View {
        gridOfTiles(maxCount: 4, columns: 2, fontScale: .medium)
    }

    // MARK: - Large (6 tiles, 2×3)

    private var largeView: some View {
        gridOfTiles(maxCount: 6, columns: 2, fontScale: .large)
    }

    // MARK: - Extra-large (8 tiles, 4×2 — iPad only)

    private var extraLargeView: some View {
        gridOfTiles(maxCount: 8, columns: 4, fontScale: .medium)
    }

    // MARK: - Grid + tile rendering

    private enum TileFontScale {
        case medium
        case large

        var titleSize: CGFloat { self == .large ? 11 : 9 }
        var valueSize: CGFloat { self == .large ? 28 : 22 }
        var valueWithSparklineSize: CGFloat { self == .large ? 22 : 18 }
        var trendSize: CGFloat { self == .large ? 10 : 8 }
        var sparklineHeight: CGFloat { self == .large ? 24 : 16 }
        var sparklineLineWidth: CGFloat { self == .large ? 1.5 : 1.2 }
        var corner: CGFloat { self == .large ? 14 : 10 }
        var hPad: CGFloat { self == .large ? 12 : 8 }
        var vPad: CGFloat { self == .large ? 10 : 6 }
        var anomalyIconSize: CGFloat { self == .large ? 11 : 9 }
    }

    @ViewBuilder
    private func gridOfTiles(maxCount: Int, columns: Int, fontScale: TileFontScale) -> some View {
        let widgets = Array((entry.snapshot?.widgets ?? []).prefix(maxCount))
        let rows = Int(ceil(Double(maxCount) / Double(columns)))
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(0..<rows, id: \.self) { r in
                GridRow {
                    ForEach(0..<columns, id: \.self) { c in
                        let i = r * columns + c
                        tile(i < widgets.count ? widgets[i] : nil, fontScale: fontScale)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tile(_ widget: SnapshotWidget?, fontScale: TileFontScale) -> some View {
        let history = widget?.history ?? []
        let showSparkline =
            history.count >= 2
            && (widget?.type == .sparkline || widget?.type == .number_with_trend)
        let needsKey = widget?.needsKey == true

        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(widget?.title.uppercased() ?? "—")
                    .font(entry.theme.secondaryFont(size: fontScale.titleSize))
                    .foregroundStyle(Color(hex: entry.theme.colors.secondary))
                    .lineLimit(1)
                if widget?.anomaly == true {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: fontScale.anomalyIconSize))
                        .foregroundStyle(Color(hex: entry.theme.colors.negative))
                }
            }
            if needsKey {
                tileNeedsKeyBody(widget, fontScale: fontScale)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(widget?.value?.displayString ?? "—")
                        .font(entry.theme.primaryFont(
                            size: showSparkline ? fontScale.valueWithSparklineSize : fontScale.valueSize
                        ))
                        .foregroundStyle(Color(hex: entry.theme.colors.primary))
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                    TrendBadge(
                        history: history,
                        positive: Color(hex: entry.theme.colors.positive),
                        negative: Color(hex: entry.theme.colors.negative),
                        neutral: Color(hex: entry.theme.colors.secondary),
                        font: .system(size: fontScale.trendSize, weight: .semibold)
                    )
                }
                if showSparkline {
                    Sparkline(
                        values: history,
                        stroke: Color(hex: entry.theme.chart.stroke),
                        fillStart: Color(hex: entry.theme.chart.fillStart),
                        fillEnd: Color(hex: entry.theme.chart.fillEnd),
                        lineWidth: fontScale.sparklineLineWidth
                    )
                    .frame(height: fontScale.sparklineHeight)
                }
            }
        }
        .padding(.vertical, fontScale.vPad)
        .padding(.horizontal, fontScale.hPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            GlassSurface(
                useGlass: entry.useGlass,
                surfaceColor: Color(hex: entry.theme.colors.surface),
                borderColor: Color(hex: entry.theme.colors.border),
                cornerRadius: fontScale.corner
            )
        )
    }

    @ViewBuilder
    private func tileNeedsKeyBody(_ widget: SnapshotWidget?, fontScale: TileFontScale) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.system(size: fontScale.valueWithSparklineSize - 4, weight: .semibold))
                    .foregroundStyle(Color(hex: entry.theme.colors.accent))
                Text("Connect")
                    .font(entry.theme.primaryFont(size: fontScale.valueWithSparklineSize - 2))
                    .foregroundStyle(Color(hex: entry.theme.colors.primary))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            Text(widget?.sourceName ?? "Add API key")
                .font(entry.theme.secondaryFont(size: fontScale.titleSize))
                .foregroundStyle(Color(hex: entry.theme.colors.secondary))
                .lineLimit(1)
        }
    }
}

/// Renders the widget's backdrop. Theme color when no image is set;
/// dashboard background photo (with a slight darken overlay for legibility)
/// when the user has picked one.
struct WidgetBackground: View {
    let entry: BentoEntry

    var body: some View {
        ZStack {
            Color(hex: entry.theme.colors.background)
            if entry.background == .image,
               let data = entry.backgroundImageData,
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                Color.black.opacity(0.25)
            }
        }
    }
}
