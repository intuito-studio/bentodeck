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
    }

    private func reload() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let list = try await APIClient().fetchDashboards()
            dashboards = list
            if selectedDashboardId == nil {
                selectedDashboardId = SharedStore.shared.pinnedDashboardId ?? list.first?.id
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// Let `String` drive NavigationStack destinations.
extension String: Identifiable { public var id: String { self } }
