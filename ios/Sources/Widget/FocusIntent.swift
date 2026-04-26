import AppIntents
import Foundation
import WidgetKit

/// User-facing identifier for a dashboard. Surfaces in the configuration UI
/// when adding the focus widget — the user picks "Dashboard" → list of
/// available dashboards. "Auto" (the unset state) means use whichever
/// dashboard was most recently active in the app.
struct DashboardEntity: AppEntity, Identifiable, Hashable {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Dashboard")
    }

    static let defaultQuery = DashboardEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct DashboardEntityQuery: EntityQuery {
    func entities(for ids: [DashboardEntity.ID]) async throws -> [DashboardEntity] {
        enumerate().filter { ids.contains($0.id) }
    }

    func suggestedEntities() async throws -> [DashboardEntity] {
        enumerate()
    }

    func defaultResult() async -> DashboardEntity? {
        enumerate().first
    }

    private func enumerate() -> [DashboardEntity] {
        SharedStore.shared.loadDashboards().map {
            DashboardEntity(id: $0.id, name: $0.name)
        }
    }
}

/// User-facing identifier for one widget on a dashboard. The widget query
/// reads the per-dashboard snapshot from SharedStore and lists every widget
/// in it. "Smart" (unset) means auto-pick: anomaly first, then most-recent.
struct WidgetEntity: AppEntity, Identifiable, Hashable {
    let id: String
    let dashboardId: String
    let title: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Widget")
    }

    static let defaultQuery = WidgetEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

struct WidgetEntityQuery: EntityQuery {
    func entities(for ids: [WidgetEntity.ID]) async throws -> [WidgetEntity] {
        enumerate().filter { ids.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetEntity] {
        enumerate()
    }

    private func enumerate() -> [WidgetEntity] {
        let store = SharedStore.shared
        var out: [WidgetEntity] = []
        for d in store.loadDashboards() {
            guard let snap = store.loadSnapshot(forDashboard: d.id)?.snapshot else { continue }
            for w in snap.widgets {
                out.append(WidgetEntity(id: w.id, dashboardId: d.id, title: w.title))
            }
        }
        return out
    }
}

/// Configuration the user fills in when adding the focus widget to their
/// home screen. Both fields are optional — leaving them blank gives you the
/// "smart" widget (latest dashboard, most-relevant widget). Setting one or
/// both narrows the focus.
struct BentoDeckFocusIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Pick a widget to focus on"
    static var description = IntentDescription(
        "Pin one BentoDeck widget to your home screen at full size. Leave both blank for the smart pick (anomalies first, then most-recent)."
    )

    @Parameter(title: "Dashboard")
    var dashboard: DashboardEntity?

    @Parameter(title: "Widget")
    var widget: WidgetEntity?

    static var parameterSummary: some ParameterSummary {
        Summary {
            \.$dashboard
            \.$widget
        }
    }
}
