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
        let widget = entry.snapshot?.widgets.first
        switch family {
        case .accessoryCircular:
            circular(widget)
        case .accessoryRectangular:
            rectangular(widget)
        case .accessoryInline:
            inline(widget)
        default:
            circular(widget)
        }
    }

    private func circular(_ widget: SnapshotWidget?) -> some View {
        VStack(spacing: 1) {
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

    private func rectangular(_ widget: SnapshotWidget?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(widget?.title ?? "BentoDeck")
                    .font(.caption)
                if widget?.anomaly == true {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                }
                Spacer(minLength: 0)
            }
            Text(widget?.value?.displayString ?? "—")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    private func inline(_ widget: SnapshotWidget?) -> some View {
        Text("\(widget?.title ?? "BentoDeck"): \(widget?.value?.displayString ?? "—")")
    }
}
