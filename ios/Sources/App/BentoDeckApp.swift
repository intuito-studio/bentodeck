import BackgroundTasks
import SwiftUI
import UserNotifications

@main
struct BentoDeckApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    await RefreshManager.shared.requestNotificationPermission()
                    RefreshManager.shared.scheduleNextBackgroundRefresh()
                }
        }
    }
}

/// App delegate exists solely to register the background task as early in the
/// launch sequence as Apple demands. All other lifecycle work stays in SwiftUI.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Config.refreshTaskID,
            using: nil
        ) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false); return
            }
            RefreshManager.shared.handle(refresh: refresh)
        }
        return true
    }
}
