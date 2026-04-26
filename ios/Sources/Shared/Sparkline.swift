import SwiftUI

/// Pure-SwiftUI sparkline. Dependency-free (Swift Charts is great but
/// imposes a min-deployment-target of iOS 16 anyway, and this version
/// renders identically inside a WidgetKit timeline where the
/// rasterization budget is tighter than in-app charts).
///
/// Renders the trailing series as a smoothed line + a faint area fill
/// underneath. Adapts to whatever theme stroke / fill colors are in
/// scope. If fewer than 2 points are present, draws nothing (so a
/// just-created widget doesn't show a misleading flat line).
struct Sparkline: View {
    let values: [Double]
    let stroke: Color
    let fillStart: Color
    let fillEnd: Color
    var lineWidth: CGFloat = 1.5

    var body: some View {
        GeometryReader { geo in
            if values.count >= 2 {
                let path = makePath(in: geo.size)
                let fillPath = makeFillPath(in: geo.size)

                ZStack {
                    fillPath.fill(
                        LinearGradient(
                            colors: [fillStart, fillEnd],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    path.stroke(
                        stroke,
                        style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round)
                    )
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count >= 2 else { return [] }
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 0
        let range = max(maxV - minV, 0.0001)
        let stepX = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { i, v in
            let normalized = (v - minV) / range
            // Flip y because SwiftUI's origin is top-left.
            let y = size.height * (1 - CGFloat(normalized))
            return CGPoint(x: CGFloat(i) * stepX, y: y)
        }
    }

    private func makePath(in size: CGSize) -> Path {
        var path = Path()
        let pts = points(in: size)
        guard let first = pts.first else { return path }
        path.move(to: first)
        for p in pts.dropFirst() {
            path.addLine(to: p)
        }
        return path
    }

    private func makeFillPath(in size: CGSize) -> Path {
        var path = Path()
        let pts = points(in: size)
        guard let first = pts.first, let last = pts.last else { return path }
        path.move(to: CGPoint(x: first.x, y: size.height))
        path.addLine(to: first)
        for p in pts.dropFirst() {
            path.addLine(to: p)
        }
        path.addLine(to: CGPoint(x: last.x, y: size.height))
        path.closeSubpath()
        return path
    }
}

/// Tiny up/down arrow + percent delta computed from the last two history
/// points. Returns nil view when there's not enough data to compute a
/// meaningful trend.
struct TrendBadge: View {
    let history: [Double]
    let positive: Color
    let negative: Color
    let neutral: Color
    var font: Font = .system(size: 11, weight: .semibold)

    var body: some View {
        if let (delta, current, previous) = trend() {
            let color = delta > 0 ? positive : delta < 0 ? negative : neutral
            let symbol = delta > 0 ? "arrow.up.right" : delta < 0 ? "arrow.down.right" : "minus"
            HStack(spacing: 2) {
                Image(systemName: symbol)
                Text(formatPercent(current: current, previous: previous))
            }
            .font(font)
            .foregroundStyle(color)
        }
    }

    private func trend() -> (delta: Double, current: Double, previous: Double)? {
        guard history.count >= 2 else { return nil }
        let current = history[history.count - 1]
        let previous = history[history.count - 2]
        return (current - previous, current, previous)
    }

    private func formatPercent(current: Double, previous: Double) -> String {
        guard previous != 0 else { return "—" }
        let pct = ((current - previous) / abs(previous)) * 100
        if abs(pct) < 0.05 { return "0%" }
        return String(format: "%+.1f%%", pct)
    }
}
