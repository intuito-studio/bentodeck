import Foundation
import SwiftUI

/// Cross-view bridge for deep links that need an *already-mounted* view to
/// react. The "Connect <source>" sheet, for example, lives inside
/// DashboardDetailView — when a `bentodeck://data-source-key` URL arrives at
/// the app via `onOpenURL`, RootView writes here, navigates to the
/// dashboard, and the detail view sees the pending entry on appear.
///
/// Kept deliberately small: one published optional. Don't grow this into a
/// general event bus — it's a narrow channel for "open the key sheet now."
@MainActor
final class DeepLinkRouter: ObservableObject {
    @Published var pendingKeyEntry: PendingKeyEntryPayload?
}

struct PendingKeyEntryPayload: Hashable, Identifiable {
    let sourceId: String
    let sourceName: String?
    var id: String { sourceId }
}
