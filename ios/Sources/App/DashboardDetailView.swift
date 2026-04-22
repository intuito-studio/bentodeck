import SwiftUI
import WidgetKit

struct DashboardDetailView: View {
    let dashboardId: String
    @State private var snapshot: SnapshotResponse?
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            if let snapshot {
                contentView(snapshot)
            } else if isLoading {
                ProgressView().padding()
            } else if let errorText {
                Text(errorText).foregroundStyle(.red).padding()
            }
        }
        .background((snapshot.flatMap { Color(hex: $0.theme?.colors.background ?? "#000000") }) ?? .black)
        .navigationTitle(snapshot?.name ?? "Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: dashboardId) { await reload() }
        .refreshable { await reload() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
            }
        }
    }

    @ViewBuilder
    private func contentView(_ snapshot: SnapshotResponse) -> some View {
        let theme = snapshot.theme ?? .fallback
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 12
        ) {
            ForEach(snapshot.widgets) { widget in
                WidgetCardView(widget: widget, theme: theme)
                    .frame(minHeight: 140)
            }
        }
        .padding(16)

        // Anomaly-aware banner
        ForEach(snapshot.widgets.filter { $0.anomaly }) { w in
            if let explanation = w.anomalyExplanation {
                AnomalyBanner(
                    title: w.title,
                    explanation: explanation,
                    theme: theme
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }

        if let ts = snapshot.widgets.compactMap(\.ts).max() {
            Text("Last refreshed \(ts)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.bottom, 16)
        }
    }

    private func reload() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let resp = try await APIClient().fetchSnapshot(dashboardId: dashboardId)
            snapshot = resp
            SharedStore.shared.save(snapshot: resp)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct AnomalyBanner: View {
    let title: String
    let explanation: String
    let theme: Theme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(hex: theme.colors.negative))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.footnote).fontWeight(.semibold)
                    .foregroundStyle(Color(hex: theme.colors.primary))
                Text(explanation).font(.footnote)
                    .foregroundStyle(Color(hex: theme.colors.secondary))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: theme.colors.surface))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(hex: theme.colors.negative), lineWidth: 1)
                )
        )
    }
}
