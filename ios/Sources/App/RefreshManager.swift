import BackgroundTasks
import Foundation
import UserNotifications
import WidgetKit

/// Coordinates Background App Refresh:
///   1. Apple fires BGAppRefreshTask on its own schedule.
///   2. We fetch the latest snapshot for the pinned dashboard.
///   3. We persist it to the App Group so the widget can read it.
///   4. If any widget has `anomaly == true`, we schedule a Local
///      Notification with the Opus 4.7 explanation.
///   5. We reload widget timelines.
///   6. We reschedule the next refresh.
///
/// This replaces APNs push (which requires a paid Apple Developer Program
/// account). The demo reads identically on a free personal team.
final class RefreshManager {
    static let shared = RefreshManager()

    private let api = APIClient()

    /// Schedules the next BG refresh in ~15 minutes (iOS will then decide
    /// when to actually fire it, usually within an hour).
    func scheduleNextBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Config.refreshTaskID)
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Simulators often don't support BG refresh; not fatal.
            print("BentoDeck: could not schedule BG refresh: \(error)")
        }
    }

    func handle(refresh task: BGAppRefreshTask) {
        scheduleNextBackgroundRefresh() // always reschedule first

        let work = Task {
            let (notified, reason) = await refresh()
            task.setTaskCompleted(success: notified != nil || reason == nil)
        }
        task.expirationHandler = { work.cancel() }
    }

    /// Performs one refresh cycle. Returns a tuple used by the BG task handler
    /// only; callers may ignore the return value.
    @discardableResult
    func refresh() async -> (notified: String?, reason: String?) {
        guard let dashboardId = SharedStore.shared.pinnedDashboardId else {
            return (nil, "no pinned dashboard")
        }
        do {
            let snap = try await api.fetchSnapshot(dashboardId: dashboardId)
            SharedStore.shared.save(snapshot: snap)
            WidgetCenter.shared.reloadAllTimelines()

            // Reconcile Live Activities — start one for each new anomaly,
            // update existing ones with new explanations / investigation
            // status, end ones whose widget recovered.
            if #available(iOS 16.1, *) {
                LiveActivityManager.shared.reconcile(with: snap)
            }

            // Collect any anomaly widgets and fire a Local Notification.
            // (Notification + Live Activity are complementary — notification
            // alerts the user once, Live Activity persists on the Lock Screen
            // for the duration of the incident.)
            let anomalies = snap.widgets.filter { $0.anomaly }
            if let first = anomalies.first {
                await fireAnomalyNotification(
                    title: first.title,
                    explanation: first.anomalyExplanation ?? "Something looks off."
                )
                return (first.id, nil)
            }
            return (nil, nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    func requestNotificationPermission() async {
        do {
            _ = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            print("BentoDeck: notification permission error: \(error)")
        }
    }

    private func fireAnomalyNotification(title: String, explanation: String) async {
        let content = UNMutableNotificationContent()
        content.title = "⚠︎ \(title)"
        content.body = explanation
        content.sound = .default
        // Immediate delivery.
        let req = UNNotificationRequest(
            identifier: "bentodeck-anomaly-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(req)
        } catch {
            print("BentoDeck: notification add failed: \(error)")
        }
    }
}
