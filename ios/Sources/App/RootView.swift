import SwiftUI
import WidgetKit

struct RootView: View {
    @State private var dashboards: [DashboardSummary] = []
    @State private var pageIndex: Int = 1
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && dashboards.isEmpty {
                    ProgressView().controlSize(.large)
                } else if let errorText, dashboards.isEmpty {
                    backendError(errorText)
                } else if dashboards.isEmpty {
                    emptyState
                } else if dashboards.count == 1 {
                    DashboardDetailView(dashboardId: dashboards[0].id)
                        .onAppear { pinIfNeeded(dashboards[0].id) }
                } else {
                    carousel
                }
            }
            .navigationTitle(currentTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if dashboards.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { Task { await reload() } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
        .task { await reload() }
        // Handle bentodeck:// deep links from widgets and Live Activities.
        .onOpenURL { url in handleDeepLink(url) }
    }

    // MARK: - Carousel

    private var carousel: some View {
        // Triple-buffer the dashboards: [last, ...real, first]. This gives
        // the user a duplicate-last page on the left of the first dashboard
        // and a duplicate-first page on the right of the last one, so the
        // physical swipe always succeeds. After the swipe lands on a
        // duplicate, we snap (without animation) to the equivalent real
        // index — looks identical, restores room to keep swiping.
        let pages = [dashboards.last!] + dashboards + [dashboards.first!]
        return TabView(selection: $pageIndex) {
            ForEach(pages.indices, id: \.self) { idx in
                DashboardDetailView(dashboardId: pages[idx].id)
                    .tag(idx)
                    .onAppear {
                        // Pin whichever dashboard is currently visible so
                        // widgets + future cold-launches remember it.
                        let realIdx = realIndex(forPage: idx)
                        if realIdx >= 0, realIdx < dashboards.count {
                            pinIfNeeded(dashboards[realIdx].id)
                        }
                    }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .onChange(of: pageIndex) { _, newIdx in
            handleEdgeWrap(newIdx)
        }
    }

    /// `pageIndex` lives in the extended index space (0...N+1). The user
    /// only ever lands on 0 or N+1 momentarily — we snap them back to the
    /// equivalent real index without animation.
    private func handleEdgeWrap(_ newIdx: Int) {
        let n = dashboards.count
        guard n > 1 else { return }
        if newIdx == 0 {
            snapWithoutAnimation(to: n)        // last real
        } else if newIdx == n + 1 {
            snapWithoutAnimation(to: 1)        // first real
        }
    }

    private func snapWithoutAnimation(to index: Int) {
        DispatchQueue.main.async {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                pageIndex = index
            }
        }
    }

    /// Map an extended-space page index to the underlying dashboard index.
    /// Page 0 is duplicate-last, pages 1..N are real, page N+1 is duplicate-first.
    private func realIndex(forPage page: Int) -> Int {
        let n = dashboards.count
        guard n > 0 else { return 0 }
        let mapped = page - 1
        return ((mapped % n) + n) % n
    }

    private var currentTitle: String {
        guard !dashboards.isEmpty else { return "BentoDeck" }
        if dashboards.count == 1 { return dashboards[0].name }
        return dashboards[realIndex(forPage: pageIndex)].name
    }

    private func pinIfNeeded(_ id: String) {
        if SharedStore.shared.pinnedDashboardId != id {
            SharedStore.shared.savePinnedDashboardId(id)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - Placeholder states

    private func backendError(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Can't reach the BentoDeck backend")
                .font(.headline)
            Text(message).font(.footnote).foregroundStyle(.secondary)
            Text("Base URL: \(Config.baseURL.absoluteString)")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button("Retry") { Task { await reload() } }
                .buttonStyle(.borderedProminent)
        }
        .multilineTextAlignment(.center)
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No dashboards yet")
                .font(.headline)
            Text("Open Claude Desktop and ask it to make one for you:\n“Show me Stripe MRR on my Home Screen.”")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Deep links

    private func handleDeepLink(_ url: URL) {
        guard let destination = BentoDeckLink.parse(url) else { return }
        switch destination {
        case let .dashboard(id):
            swipe(to: id)
        case .investigation:
            if let pinned = SharedStore.shared.pinnedDashboardId {
                swipe(to: pinned)
            }
        }
    }

    private func swipe(to dashboardId: String) {
        guard let realIdx = dashboards.firstIndex(where: { $0.id == dashboardId }) else { return }
        // Real index 0 ↔ extended index 1.
        pageIndex = realIdx + 1
    }

    // MARK: - Loading

    private func reload() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let list = try await APIClient().fetchDashboards()
            dashboards = list
            // Make the focus widget's AppIntent picker work: write the list
            // and prefetch each dashboard's snapshot so the widget extension
            // can read them later without hitting the network itself.
            SharedStore.shared.saveDashboards(list)

            // Restore the most recently pinned dashboard, if any, otherwise
            // start at the first.
            if let pinned = SharedStore.shared.pinnedDashboardId,
               let idx = list.firstIndex(where: { $0.id == pinned }) {
                pageIndex = idx + 1
            } else {
                pageIndex = 1
            }

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

// Let `String` drive NavigationStack destinations (kept for back-compat with
// any other navigation state that uses it).
extension String: Identifiable { public var id: String { self } }
