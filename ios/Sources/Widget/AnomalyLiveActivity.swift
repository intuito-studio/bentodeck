import ActivityKit
import SwiftUI
import WidgetKit

/// The Lock Screen + Dynamic Island UI for an in-flight anomaly.
///
/// Three layouts:
///   • Lock Screen (banner) — the wider card view with the anomaly
///     explanation, current value, and investigation status.
///   • Dynamic Island (compact / minimal / expanded) — three sizes Apple's
///     Dynamic Island system requires us to define.
struct AnomalyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AnomalyAttributes.self) { context in
            // Lock Screen / banner presentation.
            LockScreenContent(
                attributes: context.attributes,
                state: context.state
            )
            .activityBackgroundTint(Color(hex: context.attributes.themeBackgroundHex))
            .activitySystemActionForegroundColor(
                Color(hex: context.attributes.themePrimaryHex)
            )
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color(hex: context.attributes.themeNegativeHex))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.displayValue)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(hex: context.attributes.themePrimaryHex))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.widgetTitle)
                        .font(.caption)
                        .foregroundStyle(Color(hex: context.attributes.themeSecondaryHex))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.anomalyExplanation)
                            .font(.footnote)
                            .foregroundStyle(Color(hex: context.attributes.themePrimaryHex))
                            .lineLimit(3)
                        InvestigationStatusLine(state: context.state, attributes: context.attributes)
                    }
                }
            } compactLeading: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(hex: context.attributes.themeNegativeHex))
            } compactTrailing: {
                Text(context.state.displayValue)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } minimal: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(hex: context.attributes.themeNegativeHex))
            }
        }
    }
}

private struct LockScreenContent: View {
    let attributes: AnomalyAttributes
    let state: AnomalyAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(hex: attributes.themeNegativeHex))
                VStack(alignment: .leading, spacing: 1) {
                    Text(attributes.widgetTitle.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: attributes.themeSecondaryHex))
                        .lineLimit(1)
                    Text(attributes.dashboardName)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color(hex: attributes.themeSecondaryHex))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(state.displayValue)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(hex: attributes.themePrimaryHex))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }

            Text(state.anomalyExplanation)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: attributes.themePrimaryHex))
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            InvestigationStatusLine(state: state, attributes: attributes)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct InvestigationStatusLine: View {
    let state: AnomalyAttributes.ContentState
    let attributes: AnomalyAttributes

    var body: some View {
        HStack(spacing: 6) {
            switch state.investigationStatus {
            case "pending", "running":
                ProgressView()
                    .controlSize(.mini)
                Text("Claude is investigating…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(hex: attributes.themeSecondaryHex))
            case "done":
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: attributes.themeAccentHex))
                Text(state.investigationHeadline ?? "Tap for the report")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(hex: attributes.themePrimaryHex))
                    .lineLimit(1)
            case "failed":
                Text("Investigation unavailable")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: attributes.themeSecondaryHex))
            default:
                EmptyView()
            }
        }
    }
}
