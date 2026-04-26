import SwiftUI

/// Holds the per-dashboard layout state (size overrides + customized flag) and
/// brokers between the view and `SharedStore`. Owned at the parent level so
/// the toolbar's "Reset Layout" can call `reset()` and the grid re-renders.
@MainActor
final class BentoLayoutModel: ObservableObject {
    @Published private(set) var customized: Bool = false
    @Published private(set) var sizeOverrides: [String: LayoutSize] = [:]

    private let dashboardId: String
    private let store: SharedStore

    init(dashboardId: String, store: SharedStore = .shared) {
        self.dashboardId = dashboardId
        self.store = store
        load()
    }

    private func load() {
        let s = store.loadLayoutState(dashboardId: dashboardId)
        customized = s.customized
        sizeOverrides = s.sizeOverrides
    }

    /// Cycle the named widget to the next size. The first cycle on a virgin
    /// dashboard seeds every widget's current auto-layout size into the
    /// override map first — without that, the other widgets would reset to
    /// `.small` the moment one is touched.
    func cycle(widgetId: String, in widgets: [SnapshotWidget]) {
        if !customized {
            let defaults = BentoLayout.defaultSizes(count: widgets.count)
            for (i, w) in widgets.enumerated() {
                let s = i < defaults.count ? defaults[i] : .small
                sizeOverrides[w.id] = s
            }
            customized = true
        }
        let current = sizeOverrides[widgetId] ?? .small
        sizeOverrides[widgetId] = current.next
        save()
    }

    func reset() {
        customized = false
        sizeOverrides = [:]
        store.resetLayoutState(dashboardId: dashboardId)
    }

    /// Resolve the size to render for a widget given the current state.
    /// Read-only — used both by the packer and the resize-cycle calc.
    func size(for widgetId: String, in widgets: [SnapshotWidget]) -> LayoutSize {
        if let s = sizeOverrides[widgetId] { return s }
        if customized { return .small }
        let defaults = BentoLayout.defaultSizes(count: widgets.count)
        guard let idx = widgets.firstIndex(where: { $0.id == widgetId }), idx < defaults.count else {
            return .small
        }
        return defaults[idx]
    }

    private func save() {
        let state = DashboardLayoutState(customized: customized, sizeOverrides: sizeOverrides)
        store.saveLayoutState(state, dashboardId: dashboardId)
    }
}

/// The dashboard's bento-grid surface.
///
/// Renders widgets onto a 2-column grid using `BentoLayout`, with iOS Home
/// Screen-style edit mode: long-press anywhere to enter, each card wiggles
/// gently with a per-id phase stagger, and tapping the bottom-right handle
/// cycles the widget through `small → wide → large → tall → small`.
struct BentoGridView: View {
    let widgets: [SnapshotWidget]
    let theme: Theme
    @Binding var editMode: Bool
    @ObservedObject var model: BentoLayoutModel
    let onAnomalyTap: (SnapshotWidget) -> Void

    private let columns = BentoLayout.columns
    private let gap: CGFloat = 12
    private let hPadding: CGFloat = 16
    private let vPadding: CGFloat = 12
    private let minRowHeight: CGFloat = 120
    private let maxRowHeight: CGFloat = 280

    var body: some View {
        GeometryReader { geo in
            let packed = computePacked()
            let totalRows = max(1, BentoLayout.rowCount(packed))
            let columnWidth = max(0, (geo.size.width - 2 * hPadding - gap * CGFloat(columns - 1)) / CGFloat(columns))
            let rowHeight = clampedRowHeight(available: geo.size.height - 2 * vPadding, rows: totalRows)
            let contentHeight = rowHeight * CGFloat(totalRows) + gap * CGFloat(max(0, totalRows - 1))
            let totalHeight = max(contentHeight + 2 * vPadding, geo.size.height)
            let fits = (contentHeight + 2 * vPadding) <= geo.size.height

            ScrollView {
                ZStack(alignment: .topLeading) {
                    if editMode {
                        // Tap-to-exit catcher behind the cards.
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: geo.size.width, height: totalHeight)
                            .onTapGesture { exitEditMode() }
                    }

                    ForEach(packed, id: \.id) { p in
                        if let widget = widgets.first(where: { $0.id == p.id }) {
                            let w = columnWidth * CGFloat(p.cell.size.cols) + gap * CGFloat(max(0, p.cell.size.cols - 1))
                            let h = rowHeight * CGFloat(p.cell.size.rows) + gap * CGFloat(max(0, p.cell.size.rows - 1))
                            let x = hPadding + CGFloat(p.cell.col) * (columnWidth + gap)
                            let y = vPadding + CGFloat(p.cell.row) * (rowHeight + gap)

                            BentoCell(
                                widget: widget,
                                theme: theme,
                                size: p.cell.size,
                                cellHeight: h,
                                editMode: editMode,
                                onLongPress: enterEditMode,
                                onAnomalyTap: { onAnomalyTap(widget) },
                                onResize: { model.cycle(widgetId: widget.id, in: widgets) }
                            )
                            .frame(width: w, height: h)
                            .offset(x: x, y: y)
                            .animation(.spring(response: 0.42, dampingFraction: 0.85), value: p.cell)
                        }
                    }
                }
                .frame(width: geo.size.width, height: totalHeight, alignment: .topLeading)
            }
            .scrollDisabled(fits)
        }
    }

    private func clampedRowHeight(available: CGFloat, rows: Int) -> CGFloat {
        guard rows > 0, available > 0 else { return minRowHeight }
        let raw = available / CGFloat(rows)
        return min(maxRowHeight, max(minRowHeight, raw))
    }

    private func computePacked() -> [PackedWidget<String>] {
        let items = widgets.map { (id: $0.id, size: model.size(for: $0.id, in: widgets)) }
        return BentoLayout.pack(items)
    }

    private func enterEditMode() {
        if editMode { return }
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            editMode = true
        }
    }

    private func exitEditMode() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            editMode = false
        }
    }
}

// MARK: - One cell

private struct BentoCell: View {
    let widget: SnapshotWidget
    let theme: Theme
    let size: LayoutSize
    let cellHeight: CGFloat
    let editMode: Bool
    let onLongPress: () -> Void
    let onAnomalyTap: () -> Void
    let onResize: () -> Void

    /// Treat any cell taller than ~200pt as hero — even a `.small` cell ends
    /// up that big in the auto-layout for 3 widgets, where the smalls stretch
    /// to fill the remaining vertical space below the wide hero. Without this
    /// threshold the bottom row of a 3-widget dashboard looks half-empty.
    private var displaySize: WidgetDisplaySize {
        if size == .small && cellHeight < 200 { return .compact }
        return .hero
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            cardContent
                .allowsHitTesting(!editMode)
            if editMode {
                Button(action: onResize) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(.white)
                                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        )
                }
                .buttonStyle(.plain)
                .padding(10)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Resize widget")
            }
        }
        .modifier(WiggleEffect(active: editMode, seed: widget.id))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        // simultaneousGesture (not .onLongPressGesture) so anomaly cards
        // wrapped in a Button still enter edit mode — Button consumes the
        // touch sequence and would otherwise swallow .onLongPressGesture.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35).onEnded { _ in onLongPress() }
        )
    }

    @ViewBuilder
    private var cardContent: some View {
        let card = WidgetCardView(widget: widget, theme: theme, displaySize: displaySize)
        if !editMode, widget.anomaly, widget.investigationId != nil {
            Button(action: onAnomalyTap) { card }
                .buttonStyle(.plain)
        } else {
            card
        }
    }
}

// MARK: - Wiggle

private struct WiggleEffect: ViewModifier {
    let active: Bool
    let seed: String

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 0.04, paused: !active)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let phase = Double(abs(seed.hashValue) % 1000) / 1000.0
            // ±0.7° at ~1Hz, staggered per widget so cells don't pulse in sync.
            let angle = active ? sin((t + phase) * 6.0) * 0.7 : 0
            content.rotationEffect(.degrees(angle))
        }
    }
}
