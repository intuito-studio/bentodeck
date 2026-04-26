import SwiftUI

/// Single screen-filling background owned by `RootView`. Reads the visible
/// dashboard's theme color and (optional) photo and renders them once,
/// behind the carousel.
///
/// Hoisting the image up here is what fixes the laggy / double-rendered
/// look when the user swiped between dashboards: with the image attached
/// to each `DashboardDetailView`, two photos overlapped during the
/// transition. Now there's exactly one photo on screen and we cross-fade
/// it smoothly when the carousel snaps to a new page.
struct SharedBackgroundView: View {
    let dashboardId: String?

    var body: some View {
        let kind = dashboardId.map { SharedStore.shared.loadBackground(dashboardId: $0) } ?? .theme
        let theme = themeFor(dashboardId)
        let image = (kind == .image && dashboardId != nil)
            ? BackgroundImageCache.shared.image(forDashboardId: dashboardId!)
            : nil

        ZStack {
            Color(hex: theme?.colors.background ?? "#000000")
                .ignoresSafeArea()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .transition(.opacity)
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        // The id() forces SwiftUI to treat each dashboard's background as
        // a fresh subview, which means transitions actually cross-fade
        // (.opacity transition above) rather than mutating in place.
        .id(dashboardId ?? "<none>")
        .animation(.easeInOut(duration: 0.35), value: dashboardId)
    }

    private func themeFor(_ id: String?) -> Theme? {
        guard let id else { return nil }
        return SharedStore.shared.loadSnapshot(forDashboard: id)?.snapshot.theme
    }
}
