import SwiftUI

/// The card surface used by widget cards in the in-app dashboard and by the
/// home-screen widget tiles. When the user has set a background image on the
/// dashboard, switch to Apple's Liquid Glass material so the cards refract
/// the photo behind them; otherwise stay with the theme's solid surface
/// color so the dashboard reads cleanly on a flat background.
///
/// Liquid Glass (`.glassEffect(in:)`) is iOS 26+; older systems get
/// `.ultraThinMaterial`, which provides a similar (less refractive) frost.
struct GlassSurface: View {
    let useGlass: Bool
    let surfaceColor: Color
    let borderColor: Color
    var cornerRadius: CGFloat = 16

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if useGlass {
                glassFill(shape: shape)
            } else {
                shape.fill(surfaceColor)
            }
            shape.stroke(borderColor, lineWidth: useGlass ? 0.6 : 1)
        }
    }

    @ViewBuilder
    private func glassFill(shape: RoundedRectangle) -> some View {
        if #available(iOS 26.0, *) {
            // Liquid Glass — refractive, picks up motion + the image behind.
            Color.clear.glassEffect(in: shape)
        } else {
            // Frosted-material fallback for iOS 17–25.
            shape.fill(.ultraThinMaterial)
        }
    }
}
