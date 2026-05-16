import UIKit
import UserNotifications

// MARK: - PomodoroNotificationDelegate

/// Bridges UNUserNotificationCenter callbacks into ``PomodoroStore`` on the main actor.
final class PomodoroNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PomodoroNotificationDelegate()

    func configure() {
        PomodoroNotificationService.registerCategoriesIfNeeded()
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        guard notification.request.identifier == PomodoroNotificationService.phaseEndRequestId else {
            completionHandler([])
            return
        }
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.notification.request.identifier == PomodoroNotificationService.phaseEndRequestId else {
            completionHandler()
            return
        }
        Task { @MainActor in
            switch response.actionIdentifier {
            case "POMODORO_PAUSE":
                PomodoroStore.shared.pauseFromNotification()
            case "POMODORO_SKIP":
                PomodoroStore.shared.skipPhaseFromNotification()
            default:
                break
            }
            completionHandler()
        }
    }
}
