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
                    ZStack {
                        SharedBackgroundView(dashboardId: dashboards[0].id)
                        DashboardDetailView(dashboardId: dashboards[0].id)
                            .onAppear { pinIfNeeded(dashboards[0].id) }
                    }
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

    @State private var scrolledPage: Int? = 1

    private var carousel: some View {
        GeometryReader { geo in
            carouselBody(size: geo.size)
        }
    }

    @ViewBuilder
    private func carouselBody(size: CGSize) -> some View {
        // Triple-buffer: [last, ...real, first]. After a swipe lands on a
        // duplicate edge, snap (without animation) to the equivalent real
        // index — looks identical, lets the user keep swiping.
        let pages = [dashboards.last!] + dashboards + [dashboards.first!]
        let n = dashboards.count
        ZStack(alignment: .bottom) {
            SharedBackgroundView(dashboardId: currentVisibleDashboardId)
            scrollLayer(pages: pages, n: n, size: size)
            pageIndicator(count: n, page: realIndex(forPage: pageIndex))
                .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private func scrollLayer(pages: [DashboardSummary], n: Int, size: CGSize) -> some View {
        let scroll = ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(pages.indices, id: \.self) { idx in
                    DashboardDetailView(
                        dashboardId: pages[idx].id,
                        isActive: idx == pageIndex
                    )
                    .frame(width: size.width, height: size.height)
                    .id(idx)
                }
            }
            .scrollTargetLayout()
        }
        scroll
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrolledPage, anchor: .center)
            .onAppear { scrolledPage = pageIndex }
            .onChange(of: scrolledPage) { _, newIdx in
                handleScrollChanged(newIdx)
            }
            .onChange(of: pageIndex) { _, newIdx in
                syncScrollToPage(newIdx)
            }
    }

    private func handleScrollChanged(_ newIdx: Int?) {
        guard let newIdx else { return }
        let n = dashboards.count
        pageIndex = newIdx
        if n > 1, newIdx == 0 {
            snapScroll(to: n)
        } else if n > 1, newIdx == n + 1 {
            snapScroll(to: 1)
        }
        let realIdx = realIndex(forPage: newIdx)
        if realIdx >= 0, realIdx < dashboards.count {
            pinIfNeeded(dashboards[realIdx].id)
        }
    }

    private func syncScrollToPage(_ newIdx: Int) {
        // External page changes (e.g. deep links) sync into the scroll
        // position with no animation so they land instantly.
        guard scrolledPage != newIdx else { return }
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { scrolledPage = newIdx }
    }

    /// Move the ScrollView's position without animating it — used for the
    /// edge-wrap snap. Wrapped in DispatchQueue.main.async so the snap
    /// happens after the user's swipe transition has fully landed; doing
    /// it synchronously inside the onChange block fights the in-flight
    /// scroll-target animation and leaves the carousel in a half-state.
    private func snapScroll(to index: Int) {
        DispatchQueue.main.async {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                scrolledPage = index
            }
        }
    }

    /// Compact iOS-style page-indicator dots. Drawn on top of the carousel
    /// at the bottom; the carousel content has enough room above them since
    /// the dashboard's "Last refreshed" footer keeps a small bottom inset.
    private func pageIndicator(count: Int, page: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == page ? Color.primary.opacity(0.85) : Color.secondary.opacity(0.35))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
        .allowsHitTesting(false)
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

    private var currentVisibleDashboardId: String? {
        guard !dashboards.isEmpty else { return nil }
        if dashboards.count == 1 { return dashboards[0].id }
        return dashboards[realIndex(forPage: pageIndex)].id
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
