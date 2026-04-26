import SwiftUI
import WidgetKit

struct RootView: View {
    @State private var dashboards: [DashboardSummary] = []
    @State private var selectedDashboardId: String?
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && dashboards.isEmpty {
                    ProgressView().controlSize(.large)
                } else if let errorText, dashboards.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Can't reach the BentoDeck backend")
                            .font(.headline)
                        Text(errorText).font(.footnote).foregroundStyle(.secondary)
                        Text("Base URL: \(Config.baseURL.absoluteString)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Button("Retry") { Task { await reload() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .multilineTextAlignment(.center)
                    .padding()
                } else {
                    DashboardListView(
                        dashboards: dashboards,
                        selectedDashboardId: $selectedDashboardId
                    )
                }
            }
            .navigationTitle("BentoDeck")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .navigationDestination(item: $selectedDashboardId) { id in
                DashboardDetailView(dashboardId: id)
                    .onAppear {
                        SharedStore.shared.savePinnedDashboardId(id)
                        WidgetCenter.shared.reloadAllTimelines()
                    }
            }
        }
        .task { await reload() }
        // Handle bentodeck:// deep links from widgets and Live Activities.
        .onOpenURL { url in
            handleDeepLink(url)
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard let destination = BentoDeckLink.parse(url) else { return }
        switch destination {
        case let .dashboard(id):
            selectedDashboardId = id
        case let .investigation(_, _):
            // Investigation links are handled by DashboardDetailView's own
            // navigation destination once we land on a dashboard. For now
            // we just open the app at the most recently pinned dashboard;
            // the user is one tap away from the report.
            if let pinned = SharedStore.shared.pinnedDashboardId {
                selectedDashboardId = pinned
            }
        }
    }

    private func reload() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let list = try await APIClient().fetchDashboards()
            dashboards = list
            // Write the summary list so the focus widget's AppIntent picker
            // can enumerate dashboards without having to call the backend
            // itself (widget network access is unreliable).
            SharedStore.shared.saveDashboards(list)
            if selectedDashboardId == nil {
                selectedDashboardId = SharedStore.shared.pinnedDashboardId ?? list.first?.id
            }
            // Best-effort: prefetch each dashboard's snapshot in parallel and
            // mirror it into the per-dashboard slot. Failures here are
            // silently dropped — the picker simply won't show widgets for
            // dashboards that haven't loaded yet.
            await withTaskGroup(of: Void.self) { group in
                for dash in list {
                    group.addTask {
                        if let snap = try? await APIClient().fetchSnapshot(dashboardId: dash.id) {
                            SharedStore.shared.saveSnapshot(snap, forDashboard: dash.id)
                        }
                    }
                }
            }
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// Let `String` drive NavigationStack destinations.
extension String: Identifiable { public var id: String { self } }
