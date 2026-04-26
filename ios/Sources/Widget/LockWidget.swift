import SwiftUI
import WidgetKit

struct LockWidget: Widget {
    let kind = "LockWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BentoTimelineProvider()) { entry in
            LockWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("BentoDeck — Lock")
        .description("Glance at your top number without unlocking.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct LockWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: BentoEntry

    var body: some View {
        // Pick the most-relevant widget for the lock surface: an anomalous one
        // if the dashboard is currently anomalous, otherwise the first widget.
        let widgets = entry.snapshot?.widgets ?? []
        let widget = widgets.first(where: \.anomaly) ?? widgets.first

        switch family {
        case .accessoryCircular:
            circular(widget)
        case .accessoryRectangular:
            rectangular(widget, totalCount: widgets.count)
        case .accessoryInline:
            inline(widget)
        default:
            circular(widget)
        }
    }

    private func circular(_ widget: SnapshotWidget?) -> some View {
        VStack(spacing: 1) {
            if widget?.anomaly == true {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .bold))
            }
            Text(widget?.value?.displayString ?? "—")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            if let title = widget?.title {
                Text(title)
                    .font(.system(size: 8, weight: .medium))
                    .lineLimit(1)
            }
        }
        .padding(2)
    }

    private func rectangular(_ widget: SnapshotWidget?, totalCount: Int) -> some View {
        // The accessory-rectangular slot is wide enough to show the title +
        // big value plus a tiny sparkline if we have history. When there
        // are multiple widgets in the dashboard, hint that with "+N" so the
        // user knows there's more behind it.
        let history = widget?.history ?? []
        let showSparkline = history.count >= 2
        let extras = max(0, totalCount - 1)

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(widget?.title ?? "BentoDeck")
                    .font(.caption)
                    .lineLimit(1)
                if widget?.anomaly == true {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                }
                Spacer(minLength: 0)
                if extras > 0 {
                    Text("+\(extras)")
                        .font(.system(size: 10, weight: .semibold))
                        .opacity(0.7)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(widget?.value?.displayString ?? "—")
                    .font(.system(size: showSparkline ? 16 : 22, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if showSparkline {
                    Sparkline(
                        values: history,
                        stroke: .primary,
                        fillStart: .clear,
                        fillEnd: .clear,
                        lineWidth: 1.0
                    )
                    .frame(height: 14)
                }
            }
        }
    }

    private func inline(_ widget: SnapshotWidget?) -> some View {
        // Inline lives above the clock — must be a single line of text.
        if widget?.anomaly == true {
            return Text("⚠ \(widget?.title ?? "BentoDeck"): \(widget?.value?.displayString ?? "—")")
        }
        return Text("\(widget?.title ?? "BentoDeck"): \(widget?.value?.displayString ?? "—")")
    }
}
