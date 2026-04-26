import ActivityKit
import Foundation

/// Starts, updates, and ends BentoDeck's anomaly Live Activities.
///
/// Strategy:
///   • One activity per (widgetId, recent-anomaly) pair.
///   • Tracked by widgetId so the same anomaly persisting across multiple
///     refresh cycles updates the same activity instead of stacking.
///   • If the snapshot stops being anomalous (recovery), we end the activity
///     with a final state.
///   • If a Managed Agents investigation arrives, we update the activity to
///     show the investigation headline (so the Lock Screen banner reflects
///     "Claude is investigating…" → "Claude found X" without us touching
///     anything else).
@available(iOS 16.1, *)
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var active: [String: Activity<AnomalyAttributes>] = [:]

    /// Reconcile the set of running Live Activities against the snapshot.
    /// Call this every time we successfully fetch a fresh snapshot.
    func reconcile(with snapshot: SnapshotResponse) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let theme = snapshot.theme ?? .fallback

        // Currently anomalous widgets, keyed by id.
        let anomalous = Dictionary(
            uniqueKeysWithValues:
                snapshot.widgets.filter { $0.anomaly }.map { ($0.id, $0) }
        )

        // 1) End any active activities for widgets that recovered.
        for (id, activity) in active where anomalous[id] == nil {
            Task {
                let finalState = AnomalyAttributes.ContentState(
                    displayValue: "Resolved",
                    anomalyExplanation: "Returned to normal.",
                    investigationStatus: "",
                    investigationHeadline: nil
                )
                await activity.end(
                    ActivityContent(state: finalState, staleDate: nil),
                    dismissalPolicy: .after(Date().addingTimeInterval(60))
                )
            }
            active.removeValue(forKey: id)
        }

        // 2) Update or start activities for widgets that are anomalous now.
        for widget in anomalous.values {
            let nextState = AnomalyAttributes.ContentState(
                displayValue: widget.value?.displayString ?? "—",
                anomalyExplanation: widget.anomalyExplanation
                    ?? "Something looks off on \(widget.title).",
                investigationStatus: widget.investigationStatus ?? "",
                investigationHeadline: nil
            )

            if let existing = active[widget.id] {
                Task {
                    await existing.update(
                        ActivityContent(state: nextState, staleDate: nil)
                    )
                }
                continue
            }

            let attributes = AnomalyAttributes(
                widgetId: widget.id,
                widgetTitle: widget.title,
                dashboardName: snapshot.name,
                themeBackgroundHex: theme.colors.background,
                themePrimaryHex: theme.colors.primary,
                themeSecondaryHex: theme.colors.secondary,
                themeAccentHex: theme.colors.accent,
                themeNegativeHex: theme.colors.negative
            )

            do {
                let activity = try Activity<AnomalyAttributes>.request(
                    attributes: attributes,
                    content: ActivityContent(state: nextState, staleDate: nil),
                    pushType: nil
                )
                active[widget.id] = activity
            } catch {
                print("BentoDeck: failed to start Live Activity: \(error)")
            }
        }
    }

    /// End every active anomaly Live Activity, immediately. Useful for
    /// debug/demo reset and at app shutdown.
    func endAll() {
        for (_, activity) in active {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        active.removeAll()
    }
}
