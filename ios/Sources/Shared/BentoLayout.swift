import Foundation

/// One of the four widget sizes the in-app bento dashboard supports. Modelled
/// on iOS Home Screen widget sizes — a 2-column grid where each cell can span
/// 1 or 2 columns and 1 or 2 rows.
///
/// The cycle order (`small → wide → large → tall → small`) is what the resize
/// handle in edit mode walks through.
enum LayoutSize: String, Codable, CaseIterable, Hashable {
    case small  // 1 col × 1 row
    case wide   // 2 cols × 1 row
    case large  // 2 cols × 2 rows
    case tall   // 1 col × 2 rows

    var cols: Int {
        switch self {
        case .small, .tall: return 1
        case .wide, .large: return 2
        }
    }

    var rows: Int {
        switch self {
        case .small, .wide: return 1
        case .tall, .large: return 2
        }
    }

    /// What the bottom-right resize handle cycles to next.
    var next: LayoutSize {
        switch self {
        case .small: return .wide
        case .wide: return .large
        case .large: return .tall
        case .tall: return .small
        }
    }
}

/// A widget's placement on the 2-column bento grid after packing.
struct GridCell: Hashable {
    let col: Int
    let row: Int
    let size: LayoutSize
}

struct PackedWidget<ID: Hashable>: Hashable {
    let id: ID
    let cell: GridCell
}

fileprivate struct GridPoint: Hashable { let col: Int; let row: Int }

fileprivate extension GridCell {
    /// The grid points this cell occupies.
    var points: [GridPoint] {
        var out: [GridPoint] = []
        for c in col..<(col + size.cols) {
            for r in row..<(row + size.rows) {
                out.append(GridPoint(col: c, row: r))
            }
        }
        return out
    }
}

enum BentoLayout {
    static let columns = 2

    /// The default size BentoDeck assigns when the user hasn't customized the
    /// layout, given the total widget count. Mirrors the user's brief: 1 fills,
    /// 2 stack, 3 = wide on top + two squares below, 4 = 2×2 squares,
    /// anything more is squares scrolling down.
    static func defaultSizes(count: Int) -> [LayoutSize] {
        switch count {
        case 0: return []
        case 1: return [.large]
        case 2: return [.wide, .wide]
        case 3: return [.wide, .small, .small]
        case 4: return Array(repeating: .small, count: 4)
        default: return Array(repeating: .small, count: count)
        }
    }

    /// Pack `(id, size)` items into a 2-column grid using a simple greedy fill.
    /// Iterates rows top-down; on each row, walks the queue in order and
    /// places anything that fits without overlapping previously-placed cells.
    /// Items that don't fit roll to the next row.
    ///
    /// Intentionally order-preserving rather than optimal — that's what users
    /// expect when their dashboard re-renders.
    static func pack<ID: Hashable>(_ items: [(id: ID, size: LayoutSize)]) -> [PackedWidget<ID>] {
        var occupied: Set<GridPoint> = []
        var placed: [PackedWidget<ID>] = []
        placed.reserveCapacity(items.count)

        var queue = items
        var row = 0

        while !queue.isEmpty {
            var idx = 0
            while idx < queue.count {
                let item = queue[idx]
                if let col = firstFittingColumn(size: item.size, row: row, occupied: occupied) {
                    let cell = GridCell(col: col, row: row, size: item.size)
                    placed.append(PackedWidget(id: item.id, cell: cell))
                    for p in cell.points { occupied.insert(p) }
                    queue.remove(at: idx)
                } else {
                    idx += 1
                }
                if rowIsFull(row: row, occupied: occupied) { break }
            }
            row += 1
        }

        return placed
    }

    /// Total rows used by a packed layout. Useful for the host view to compute
    /// row height to fill the available screen.
    static func rowCount<ID: Hashable>(_ packed: [PackedWidget<ID>]) -> Int {
        packed.map { $0.cell.row + $0.cell.size.rows }.max() ?? 0
    }

    /// Pick the `LayoutSize` whose visual rect is closest to the requested
    /// width × height. Used by the resize-by-drag gesture: as the user drags
    /// the bottom-right handle, the target size is whichever standard cell
    /// dimensions best match the (start cell + drag translation) rect.
    ///
    /// `columnWidth` and `rowHeight` are the unit dimensions (1×1 cell) and
    /// `gap` is the inter-cell spacing — same numbers the grid view uses to
    /// lay everything else out.
    static func closestSize(
        toWidth targetWidth: Double,
        height targetHeight: Double,
        columnWidth: Double,
        rowHeight: Double,
        gap: Double
    ) -> LayoutSize {
        var best: LayoutSize = .small
        var bestDist = Double.infinity
        for candidate in LayoutSize.allCases {
            let cw = Double(candidate.cols) * columnWidth
                + Double(max(0, candidate.cols - 1)) * gap
            let ch = Double(candidate.rows) * rowHeight
                + Double(max(0, candidate.rows - 1)) * gap
            let dx = cw - targetWidth
            let dy = ch - targetHeight
            let dist = dx * dx + dy * dy
            if dist < bestDist {
                bestDist = dist
                best = candidate
            }
        }
        return best
    }

    private static func firstFittingColumn(
        size: LayoutSize,
        row: Int,
        occupied: Set<GridPoint>
    ) -> Int? {
        let maxStart = columns - size.cols
        guard maxStart >= 0 else { return nil }
        for startCol in 0...maxStart {
            var fits = true
            outer: for c in startCol..<(startCol + size.cols) {
                for r in row..<(row + size.rows) {
                    if occupied.contains(GridPoint(col: c, row: r)) {
                        fits = false
                        break outer
                    }
                }
            }
            if fits { return startCol }
        }
        return nil
    }

    private static func rowIsFull(row: Int, occupied: Set<GridPoint>) -> Bool {
        for col in 0..<columns {
            if !occupied.contains(GridPoint(col: col, row: row)) { return false }
        }
        return true
    }
}
