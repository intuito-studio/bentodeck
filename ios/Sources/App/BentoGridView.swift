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

    /// Set an explicit size for a widget. The first edit on a virgin dashboard
    /// seeds every widget's current auto-layout size into the override map
    /// first — without that, untouched cells would all reset to `.small` the
    /// moment one is resized.
    func setSize(_ size: LayoutSize, widgetId: String, in widgets: [SnapshotWidget]) {
        if !customized {
            let defaults = BentoLayout.defaultSizes(count: widgets.count)
            for (i, w) in widgets.enumerated() {
                let s = i < defaults.count ? defaults[i] : .small
                sizeOverrides[w.id] = s
            }
            customized = true
        }
        sizeOverrides[widgetId] = size
        save()
    }

    /// Cycle the named widget to the next size. Used as a tap fallback on the
    /// resize handle when the user touches without dragging.
    func cycle(widgetId: String, in widgets: [SnapshotWidget]) {
        let current = sizeOverrides[widgetId] ?? size(for: widgetId, in: widgets)
        setSize(current.next, widgetId: widgetId, in: widgets)
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

/// Tracks an in-flight resize drag at the grid level, so the dashed ghost
/// outline can render outside the dragged cell's frame (the ghost may need
/// to extend to where the cell *will* be after the snap).
private struct DragGhost: Equatable {
    let widgetId: String
    let targetSize: LayoutSize
}

/// The dashboard's bento-grid surface.
///
/// Renders widgets onto a 2-column grid using `BentoLayout`, with iOS Home
/// Screen-style edit mode: long-press anywhere to enter, each card wiggles
/// gently with a per-id phase stagger, and the bottom-right handle either
/// drags to a new size (with a ghost preview) or taps to cycle through sizes.
struct BentoGridView: View {
    let widgets: [SnapshotWidget]
    let theme: Theme
    @Binding var editMode: Bool
    @ObservedObject var model: BentoLayoutModel
    let onAnomalyTap: (SnapshotWidget) -> Void

    @State private var ghost: DragGhost?

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
                            let w = cellWidth(for: p.cell.size, columnWidth: columnWidth)
                            let h = cellHeight(for: p.cell.size, rowHeight: rowHeight)
                            let x = hPadding + CGFloat(p.cell.col) * (columnWidth + gap)
                            let y = vPadding + CGFloat(p.cell.row) * (rowHeight + gap)

                            BentoCell(
                                widget: widget,
                                theme: theme,
                                size: p.cell.size,
                                cellHeight: h,
                                editMode: editMode,
                                columnWidth: columnWidth,
                                rowHeight: rowHeight,
                                gap: gap,
                                onLongPress: enterEditMode,
                                onAnomalyTap: { onAnomalyTap(widget) },
                                onTapResize: {
                                    model.cycle(widgetId: widget.id, in: widgets)
                                },
                                onDragChange: { target in
                                    ghost = DragGhost(widgetId: widget.id, targetSize: target)
                                },
                                onDragEnd: { target in
                                    ghost = nil
                                    if target != p.cell.size {
                                        let gen = UIImpactFeedbackGenerator(style: .medium)
                                        gen.impactOccurred()
                                        model.setSize(target, widgetId: widget.id, in: widgets)
                                    }
                                },
                                onDragCancel: {
                                    ghost = nil
                                }
                            )
                            .frame(width: w, height: h)
                            .offset(x: x, y: y)
                            .zIndex(ghost?.widgetId == widget.id ? 1 : 0)
                            .animation(.spring(response: 0.42, dampingFraction: 0.85), value: p.cell)
                        }
                    }

                    // Dashed ghost outline showing the targeted size during a
                    // resize drag. Anchored to the dragged cell's top-left.
                    if let ghost,
                       let cell = packed.first(where: { $0.id == ghost.widgetId })?.cell {
                        let gw = cellWidth(for: ghost.targetSize, columnWidth: columnWidth)
                        let gh = cellHeight(for: ghost.targetSize, rowHeight: rowHeight)
                        let gx = hPadding + CGFloat(cell.col) * (columnWidth + gap)
                        let gy = vPadding + CGFloat(cell.row) * (rowHeight + gap)

                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                Color(hex: theme.colors.accent).opacity(0.85),
                                style: StrokeStyle(lineWidth: 2.5, dash: [8, 6])
                            )
                            .frame(width: gw, height: gh)
                            .offset(x: gx, y: gy)
                            .allowsHitTesting(false)
                            .animation(.easeOut(duration: 0.12), value: ghost.targetSize)
                    }
                }
                .frame(width: geo.size.width, height: totalHeight, alignment: .topLeading)
            }
            .scrollDisabled(fits)
        }
    }

    private func cellWidth(for size: LayoutSize, columnWidth: CGFloat) -> CGFloat {
        columnWidth * CGFloat(size.cols) + gap * CGFloat(max(0, size.cols - 1))
    }

    private func cellHeight(for size: LayoutSize, rowHeight: CGFloat) -> CGFloat {
        rowHeight * CGFloat(size.rows) + gap * CGFloat(max(0, size.rows - 1))
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
    let columnWidth: CGFloat
    let rowHeight: CGFloat
    let gap: CGFloat
    let onLongPress: () -> Void
    let onAnomalyTap: () -> Void
    let onTapResize: () -> Void
    let onDragChange: (LayoutSize) -> Void
    let onDragEnd: (LayoutSize) -> Void
    let onDragCancel: () -> Void

    @State private var dragStartSize: LayoutSize?

    private var displaySize: WidgetDisplaySize {
        if size == .small && cellHeight < 200 { return .compact }
        return .hero
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            cardContent
                .allowsHitTesting(!editMode)
            if editMode {
                resizeHandle
                    .padding(10)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .modifier(WiggleEffect(active: editMode, seed: widget.id))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35).onEnded { _ in onLongPress() }
        )
    }

    @ViewBuilder
    private var resizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.black)
            .frame(width: 36, height: 36)
            .contentShape(Circle())
            .background(
                Circle()
                    .fill(.white)
                    .frame(width: 30, height: 30)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            )
            .accessibilityLabel("Resize widget — drag, or tap to cycle")
            .gesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .global)
                    .onChanged { value in
                        if dragStartSize == nil { dragStartSize = size }
                        guard let start = dragStartSize else { return }
                        let target = sizeForDrag(translation: value.translation, from: start)
                        onDragChange(target)
                    }
                    .onEnded { value in
                        guard let start = dragStartSize else {
                            onDragCancel()
                            return
                        }
                        let target = sizeForDrag(translation: value.translation, from: start)
                        dragStartSize = nil
                        onDragEnd(target)
                    }
            )
            .simultaneousGesture(
                TapGesture().onEnded {
                    // Stationary tap (no drag movement) — cycle as a fallback.
                    if dragStartSize == nil { onTapResize() }
                }
            )
    }

    /// Pick the LayoutSize whose visual rect is closest to the cell's current
    /// rect plus the drag translation. The ghost outline tracks this.
    private func sizeForDrag(translation: CGSize, from startSize: LayoutSize) -> LayoutSize {
        let startW = CGFloat(startSize.cols) * columnWidth + CGFloat(max(0, startSize.cols - 1)) * gap
        let startH = CGFloat(startSize.rows) * rowHeight + CGFloat(max(0, startSize.rows - 1)) * gap
        return BentoLayout.closestSize(
            toWidth: Double(max(0, startW + translation.width)),
            height: Double(max(0, startH + translation.height)),
            columnWidth: Double(columnWidth),
            rowHeight: Double(rowHeight),
            gap: Double(gap)
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
