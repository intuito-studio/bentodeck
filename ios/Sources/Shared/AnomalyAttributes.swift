import ActivityKit
import Foundation

/// Live Activity attributes for an in-flight anomaly.
///
/// `Static` (set when the activity starts):
///   widgetTitle, dashboardName, themeName, themeColors
///
/// `ContentState` (mutable across activity.update calls):
///   value, anomalyExplanation, investigationStatus, investigationHeadline
///
/// The Lock Screen / Dynamic Island UI lives in the widget extension as a
/// `LiveActivity` widget. It's the third Apple ambient surface BentoDeck
/// occupies — alongside Home Screen widgets and Lock Screen widgets — and
/// works on free personal team signing because it doesn't require APNs
/// (`Activity.request` from the app suffices).
struct AnomalyAttributes: ActivityAttributes {
    public typealias AnomalyState = ContentState

    public struct ContentState: Codable, Hashable {
        var displayValue: String
        var anomalyExplanation: String
        var investigationStatus: String  // "pending" | "running" | "done" | "failed" | ""
        var investigationHeadline: String?
    }

    var widgetId: String
    var widgetTitle: String
    var dashboardName: String
    // Embed the resolved theme so the Live Activity can render in the same
    // colors as the rest of the app. We can't pull it dynamically because
    // ActivityKit serialises this once at request time.
    var themeBackgroundHex: String
    var themePrimaryHex: String
    var themeSecondaryHex: String
    var themeAccentHex: String
    var themeNegativeHex: String
}
