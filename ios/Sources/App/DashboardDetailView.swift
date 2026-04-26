import SwiftUI
import WidgetKit

struct DashboardDetailView: View {
    let dashboardId: String
    @State private var snapshot: SnapshotResponse?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var selectedInvestigation: SelectedInvestigation?
    @State private var editMode: Bool = false
    @StateObject private var layoutModel: BentoLayoutModel

    init(dashboardId: String) {
        self.dashboardId = dashboardId
        _layoutModel = StateObject(wrappedValue: BentoLayoutModel(dashboardId: dashboardId))
    }

    var body: some View {
        Group {
            if let snapshot {
                contentView(snapshot)
            } else if isLoading {
                ProgressView().padding()
            } else if let errorText {
                Text(errorText).foregroundStyle(.red).padding()
            } else {
                Color.clear
            }
        }
        .background((snapshot.flatMap { Color(hex: $0.theme?.colors.background ?? "#000000") }) ?? .black)
        .navigationTitle(snapshot?.name ?? "Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: dashboardId) { await reload() }
        .refreshable { await reload() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if editMode {
                    Button("Done") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            editMode = false
                        }
                    }
                    .fontWeight(.semibold)
                } else {
                    Menu {
                        Button {
                            Task { await reload() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        Button {
                            withAnimation { editMode = true }
                        } label: {
                            Label("Edit Layout", systemImage: "rectangle.3.group")
                        }
                        if layoutModel.customized {
                            Button(role: .destructive) {
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                    layoutModel.reset()
                                }
                            } label: {
                                Label("Reset Layout", systemImage: "arrow.counterclockwise")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .navigationDestination(item: $selectedInvestigation) { selection in
            InvestigationDetailView(
                investigationId: selection.investigationId,
                widgetTitle: selection.widgetTitle,
                theme: selection.theme
            )
        }
    }

    @ViewBuilder
    private func contentView(_ snapshot: SnapshotResponse) -> some View {
        let theme = snapshot.theme ?? .fallback
        VStack(spacing: 0) {
            BentoGridView(
                widgets: snapshot.widgets,
                theme: theme,
                editMode: $editMode,
                model: layoutModel,
                onAnomalyTap: { widget in
                    if let invId = widget.investigationId {
                        selectedInvestigation = SelectedInvestigation(
                            investigationId: invId,
                            widgetTitle: widget.title,
                            theme: theme
                        )
                    }
                }
            )
            .frame(maxHeight: .infinity)

            if !editMode {
                anomalyAndFooter(snapshot: snapshot, theme: theme)
            }
        }
    }

    @ViewBuilder
    private func anomalyAndFooter(snapshot: SnapshotResponse, theme: Theme) -> some View {
        VStack(spacing: 0) {
            ForEach(snapshot.widgets.filter { $0.anomaly }) { w in
                if let explanation = w.anomalyExplanation {
                    Button {
                        if let invId = w.investigationId {
                            selectedInvestigation = SelectedInvestigation(
                                investigationId: invId,
                                widgetTitle: w.title,
                                theme: theme
                            )
                        }
                    } label: {
                        AnomalyBanner(
                            title: w.title,
                            explanation: explanation,
                            investigationStatus: w.investigationStatus,
                            hasInvestigation: w.investigationId != nil,
                            theme: theme
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(w.investigationId == nil)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }

            if let ts = snapshot.widgets.compactMap(\.ts).max() {
                Text("Last refreshed \(ts)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
            }
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

private struct SelectedInvestigation: Hashable, Identifiable {
    let investigationId: String
    let widgetTitle: String
    let theme: Theme
    var id: String { investigationId }
}

private struct AnomalyBanner: View {
    let title: String
    let explanation: String
    let investigationStatus: String?
    let hasInvestigation: Bool
    let theme: Theme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(hex: theme.colors.negative))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title).font(.footnote).fontWeight(.semibold)
                        .foregroundStyle(Color(hex: theme.colors.primary))
                    if hasInvestigation {
                        investigationBadge
                    }
                }
                Text(explanation).font(.footnote)
                    .foregroundStyle(Color(hex: theme.colors.secondary))
                if hasInvestigation {
                    HStack(spacing: 4) {
                        Text("Tap for Claude's full investigation")
                            .font(.caption2)
                            .foregroundStyle(Color(hex: theme.colors.accent))
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(Color(hex: theme.colors.accent))
                    }
                    .padding(.top, 2)
                }
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

    @ViewBuilder
    private var investigationBadge: some View {
        let label: String? = {
            switch investigationStatus {
            case "pending", "running": return "Investigating…"
            case "done": return "Report ready"
            case "failed": return nil
            default: return nil
            }
        }()
        if let label {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color(hex: theme.colors.accent))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().stroke(Color(hex: theme.colors.accent), lineWidth: 1)
                )
        }
    }
}
