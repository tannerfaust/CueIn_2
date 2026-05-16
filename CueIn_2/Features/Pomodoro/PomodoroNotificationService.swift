import Foundation
import UserNotifications

// MARK: - PomodoroNotificationService

enum PomodoroNotificationService {
    static let phaseEndRequestId = "pomodoro.phaseEnd"
    static let categoryId = "POMODORO_PHASE"
    private static let pauseActionId = "POMODORO_PAUSE"
    private static let skipActionId = "POMODORO_SKIP"

    static func registerCategoriesIfNeeded() {
        let pause = UNNotificationAction(
            identifier: pauseActionId,
            title: "Pause",
            options: []
        )
        let skip = UNNotificationAction(
            identifier: skipActionId,
            title: "Skip",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: categoryId,
            actions: [pause, skip],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    @MainActor
    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            break
        @unknown default:
            break
        }
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    @MainActor
    static func cancelPhaseEndNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [phaseEndRequestId])
    }

    /// Schedules a single fire at `endDate` (clamped to a minimum interval so the system accepts the request).
    @MainActor
    static func schedulePhaseEndNotification(endDate: Date, phase: PomodoroPhase, body: String) async {
        cancelPhaseEndNotification()
        let interval = max(1, endDate.timeIntervalSinceNow)
        let content = UNMutableNotificationContent()
        content.title = "CueIn — \(phase.title)"
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryId
        content.threadIdentifier = "pomodoro"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: phaseEndRequestId, content: content, trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // Non-fatal; in-app timer still runs.
        }
    }
}
