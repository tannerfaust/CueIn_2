import Foundation
import Observation
import UIKit

// MARK: - Focus coach token

struct PomodoroFocusCoachToken: Identifiable, Equatable {
    let id = UUID()
}

// MARK: - PomodoroDurationPreferences

/// Bundled timer lengths so `@Observable` sees **one** stored mutation instead of four interdependent properties
/// (nested `access` / `didSet` on `workMinutes` was still able to blow the stack / fault the registrar).
struct PomodoroDurationPreferences: Equatable, Sendable {
    var workMinutes: Int
    var shortBreakMinutes: Int
    var longBreakMinutes: Int
    var longBreakEvery: Int

    static func clamped(_ raw: Self) -> Self {
        Self(
            workMinutes: max(5, min(120, raw.workMinutes)),
            shortBreakMinutes: max(1, min(30, raw.shortBreakMinutes)),
            longBreakMinutes: max(5, min(45, raw.longBreakMinutes)),
            longBreakEvery: max(2, min(8, raw.longBreakEvery))
        )
    }
}

// MARK: - PomodoroStore

@MainActor
@Observable
final class PomodoroStore {
    static let shared = PomodoroStore()

    private(set) var phase: PomodoroPhase = .work
    private(set) var isRunning = false
    /// Wall-clock end for the active countdown. `nil` when idle or paused.
    private(set) var phaseEndsAt: Date?
    /// Frozen remaining seconds while paused.
    private(set) var pausedRemainingSeconds: Int?
    /// Whole seconds remaining for UI; updated each tick from `phaseEndsAt` or pause storage.
    private(set) var remainingSeconds: Int = 25 * 60

    /// Counts down completed **work** blocks until the next long break.
    private(set) var workoutsUntilLongBreak: Int = 4

    var focusCoachPresentation: PomodoroFocusCoachToken?

    /// Single stored preference bundle — avoids observation re-entrancy across related ints.
    var durationPreferences: PomodoroDurationPreferences {
        didSet {
            let clamped = PomodoroDurationPreferences.clamped(durationPreferences)
            if clamped != durationPreferences {
                durationPreferences = clamped
                return
            }
            persistDurationPreferences()
            alignWorkoutsCounterIfNeeded()
            resyncIfIdleOrPaused()
        }
    }

    var notifyWhenPhaseEnds = true {
        didSet { persistNonDurationPreferences() }
    }

    var keepScreenAwakeDuringWork = true {
        didSet { persistNonDurationPreferences(); syncIdleTimer() }
    }

    var showFocusCoachOnWorkStart = false {
        didSet { persistNonDurationPreferences() }
    }

    private static let defaults = UserDefaults.standard
    private static let keyWork = "cuein.pomodoro.workMinutes.v1"
    private static let keyShort = "cuein.pomodoro.shortBreakMinutes.v1"
    private static let keyLong = "cuein.pomodoro.longBreakMinutes.v1"
    private static let keyEvery = "cuein.pomodoro.longBreakEvery.v1"
    private static let keyNotify = "cuein.pomodoro.notifyPhaseEnd.v1"
    private static let keyAwake = "cuein.pomodoro.keepAwake.v1"
    private static let keyCoach = "cuein.pomodoro.focusCoach.v1"

    private var tickTask: Task<Void, Never>?

    private init() {
        let d = Self.defaults
        durationPreferences = PomodoroDurationPreferences.clamped(
            PomodoroDurationPreferences(
                workMinutes: d.object(forKey: Self.keyWork) as? Int ?? 25,
                shortBreakMinutes: d.object(forKey: Self.keyShort) as? Int ?? 5,
                longBreakMinutes: d.object(forKey: Self.keyLong) as? Int ?? 15,
                longBreakEvery: d.object(forKey: Self.keyEvery) as? Int ?? 4
            )
        )
        notifyWhenPhaseEnds = d.object(forKey: Self.keyNotify) as? Bool ?? true
        keepScreenAwakeDuringWork = d.object(forKey: Self.keyAwake) as? Bool ?? true
        showFocusCoachOnWorkStart = d.object(forKey: Self.keyCoach) as? Bool ?? false
        workoutsUntilLongBreak = durationPreferences.longBreakEvery
        remainingSeconds = durationSeconds(for: phase)
        alignWorkoutsCounterIfNeeded()
    }

    var progress: Double {
        let total = max(1, durationSeconds(for: phase))
        return 1 - Double(remainingSeconds) / Double(total)
    }

    var isOnWorkPhase: Bool { phase == .work }

    var canSkipPhase: Bool { isRunning || pausedRemainingSeconds != nil }

    // MARK: Controls

    func start() {
        if isRunning { return }
        if let paused = pausedRemainingSeconds {
            resume(from: paused)
            return
        }
        beginFreshWorkBlock()
    }

    func pause() {
        guard isRunning, let end = phaseEndsAt else { return }
        let left = max(0, Int(ceil(end.timeIntervalSinceNow)))
        pausedRemainingSeconds = left
        phaseEndsAt = nil
        isRunning = false
        stopTicking()
        syncIdleTimer()
        PomodoroNotificationService.cancelPhaseEndNotification()
    }

    func pauseFromNotification() {
        pause()
    }

    func skipPhaseFromNotification() {
        skipPhase()
    }

    func resetSession() {
        stopTicking()
        isRunning = false
        phase = .work
        phaseEndsAt = nil
        pausedRemainingSeconds = nil
        workoutsUntilLongBreak = durationPreferences.longBreakEvery
        remainingSeconds = durationSeconds(for: .work)
        syncIdleTimer()
        PomodoroNotificationService.cancelPhaseEndNotification()
    }

    func skipPhase() {
        guard canSkipPhase else { return }
        PomodoroNotificationService.cancelPhaseEndNotification()
        stopTicking()
        isRunning = false
        phaseEndsAt = nil
        pausedRemainingSeconds = nil
        syncIdleTimer()

        switch phase {
        case .work:
            finishWorkInterval()
        case .shortBreak, .longBreak:
            startWorkPhase(announceFocusCoach: showFocusCoachOnWorkStart)
        }
    }

    func applyNotificationToggle(_ on: Bool) async {
        if on {
            let ok = await PomodoroNotificationService.requestAuthorizationIfNeeded()
            notifyWhenPhaseEnds = ok
            persistNonDurationPreferences()
            if ok {
                await scheduleEndNotificationIfNeeded()
            }
        } else {
            notifyWhenPhaseEnds = false
            persistNonDurationPreferences()
            PomodoroNotificationService.cancelPhaseEndNotification()
        }
    }

    // MARK: - Internals

    private func beginFreshWorkBlock() {
        phase = .work
        pausedRemainingSeconds = nil
        let duration = durationSeconds(for: .work)
        remainingSeconds = duration
        let end = Date().addingTimeInterval(TimeInterval(duration))
        phaseEndsAt = end
        isRunning = true
        startTicking()
        syncIdleTimer()
        maybePresentFocusCoach()
        Task { await scheduleEndNotificationIfNeeded() }
    }

    private func resume(from seconds: Int) {
        let end = Date().addingTimeInterval(TimeInterval(max(1, seconds)))
        phaseEndsAt = end
        pausedRemainingSeconds = nil
        isRunning = true
        remainingSeconds = seconds
        startTicking()
        syncIdleTimer()
        Task { await scheduleEndNotificationIfNeeded() }
    }

    private func completeCurrentPhaseBecauseTimerFired() {
        stopTicking()
        isRunning = false
        phaseEndsAt = nil
        pausedRemainingSeconds = nil
        syncIdleTimer()
        PomodoroNotificationService.cancelPhaseEndNotification()
        CueInHaptics.impact(.medium)

        switch phase {
        case .work:
            finishWorkInterval()
        case .shortBreak, .longBreak:
            startWorkPhase(announceFocusCoach: showFocusCoachOnWorkStart)
        }
    }

    private func finishWorkInterval() {
        workoutsUntilLongBreak -= 1
        if workoutsUntilLongBreak <= 0 {
            workoutsUntilLongBreak = durationPreferences.longBreakEvery
            enterBreakPhase(.longBreak)
        } else {
            enterBreakPhase(.shortBreak)
        }
    }

    private func enterBreakPhase(_ kind: PomodoroPhase) {
        phase = kind
        pausedRemainingSeconds = nil
        let duration = durationSeconds(for: kind)
        remainingSeconds = duration
        let end = Date().addingTimeInterval(TimeInterval(duration))
        phaseEndsAt = end
        isRunning = true
        startTicking()
        syncIdleTimer()
        Task { await scheduleEndNotificationIfNeeded() }
    }

    private func startWorkPhase(announceFocusCoach: Bool) {
        phase = .work
        pausedRemainingSeconds = nil
        let duration = durationSeconds(for: .work)
        remainingSeconds = duration
        let end = Date().addingTimeInterval(TimeInterval(duration))
        phaseEndsAt = end
        isRunning = true
        startTicking()
        syncIdleTimer()
        if announceFocusCoach { maybePresentFocusCoach() }
        Task { await scheduleEndNotificationIfNeeded() }
    }

    private func maybePresentFocusCoach() {
        guard showFocusCoachOnWorkStart else { return }
        focusCoachPresentation = PomodoroFocusCoachToken()
    }

    func dismissFocusCoach() {
        focusCoachPresentation = nil
    }

    /// Catches up after suspension / background so the ring matches wall clock time.
    func refreshFromWallClockIfNeeded() {
        guard isRunning, let end = phaseEndsAt else { return }
        let left = max(0, Int(ceil(end.timeIntervalSinceNow)))
        remainingSeconds = left
        if left <= 0 {
            completeCurrentPhaseBecauseTimerFired()
        }
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func tick() {
        guard isRunning, let end = phaseEndsAt else { return }
        let left = max(0, Int(ceil(end.timeIntervalSinceNow)))
        remainingSeconds = left
        if left <= 0 {
            completeCurrentPhaseBecauseTimerFired()
        }
    }

    private func durationSeconds(for phase: PomodoroPhase) -> Int {
        switch phase {
        case .work: return max(1, durationPreferences.workMinutes) * 60
        case .shortBreak: return max(1, durationPreferences.shortBreakMinutes) * 60
        case .longBreak: return max(1, durationPreferences.longBreakMinutes) * 60
        }
    }

    private func persistDurationPreferences() {
        let d = Self.defaults
        d.set(durationPreferences.workMinutes, forKey: Self.keyWork)
        d.set(durationPreferences.shortBreakMinutes, forKey: Self.keyShort)
        d.set(durationPreferences.longBreakMinutes, forKey: Self.keyLong)
        d.set(durationPreferences.longBreakEvery, forKey: Self.keyEvery)
    }

    private func persistNonDurationPreferences() {
        let d = Self.defaults
        d.set(notifyWhenPhaseEnds, forKey: Self.keyNotify)
        d.set(keepScreenAwakeDuringWork, forKey: Self.keyAwake)
        d.set(showFocusCoachOnWorkStart, forKey: Self.keyCoach)
    }

    private func resyncIfIdleOrPaused() {
        guard !isRunning else {
            Task { await scheduleEndNotificationIfNeeded() }
            return
        }
        if let p = pausedRemainingSeconds {
            remainingSeconds = p
        } else {
            remainingSeconds = durationSeconds(for: phase)
        }
    }

    private func alignWorkoutsCounterIfNeeded() {
        let every = durationPreferences.longBreakEvery
        if workoutsUntilLongBreak > every {
            workoutsUntilLongBreak = every
        }
        if workoutsUntilLongBreak < 1 {
            workoutsUntilLongBreak = every
        }
    }

    private func syncIdleTimer() {
        let lock = keepScreenAwakeDuringWork && isRunning && phase == .work
        UIApplication.shared.isIdleTimerDisabled = lock
    }

    private func scheduleEndNotificationIfNeeded() async {
        guard notifyWhenPhaseEnds, isRunning, let end = phaseEndsAt else { return }
        let authorized = await PomodoroNotificationService.requestAuthorizationIfNeeded()
        guard authorized else { return }
        let body = notificationBody(for: phase)
        await PomodoroNotificationService.schedulePhaseEndNotification(endDate: end, phase: phase, body: body)
    }

    private func notificationBody(for phase: PomodoroPhase) -> String {
        switch phase {
        case .work:
            return "Focus block finished — take a breather."
        case .shortBreak:
            return "Short break over — ready for another focus block."
        case .longBreak:
            return "Long break over — time to ease back in."
        }
    }

    // MARK: - Data reset hook

    func resetForFreshInstall() {
        resetSession()
        durationPreferences = PomodoroDurationPreferences.clamped(
            PomodoroDurationPreferences(workMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15, longBreakEvery: 4)
        )
        notifyWhenPhaseEnds = true
        keepScreenAwakeDuringWork = true
        showFocusCoachOnWorkStart = false
        persistNonDurationPreferences()
    }
}
