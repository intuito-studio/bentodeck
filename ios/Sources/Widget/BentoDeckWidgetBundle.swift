import SwiftUI
import WidgetKit

@main
struct BentoDeckWidgetBundle: WidgetBundle {
    var body: some Widget {
        HomeWidget()
        FocusWidget()
        LockWidget()
        AnomalyLiveActivity()
    }
}
