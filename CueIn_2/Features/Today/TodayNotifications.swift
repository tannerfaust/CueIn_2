import Foundation

extension Notification.Name {
    static let cueInShowTodayFormulaPicker = Notification.Name("cuein.today.showFormulaPicker")
    static let cueInShowScheduleStartSetup = Notification.Name("cuein.today.showScheduleStartSetup")
    /// Switch to TimeMap (formula) mode and select a saved day formula. Use ``CueInShellNotification/formulaIDUserInfoKey``.
    static let cueInApplySavedFormula = Notification.Name("cuein.today.applySavedFormula")
    /// Opens the floating TimeMap block template library (same as long-press on TimeMap).
    static let cueInOpenBlockTemplateLibrary = Notification.Name("cuein.today.openBlockTemplateLibrary")
    /// Present full-screen focus on the active TimeMap block (Today).
    static let cueInOpenTimeblockFocus = Notification.Name("cuein.today.openTimeblockFocus")
    /// Switch shell to the Pomodoro tab (Hub tile, deep links, etc.).
    static let cueInOpenFocus = Notification.Name("cuein.focus.open")
    /// Switch shell to the focus audio tab.
    static let cueInOpenSounds = Notification.Name("cuein.sounds.open")
    /// Switch shell ``AppTab``; include `userInfo` ``CueInShellNotification/switchTabUserInfoKey`` = tab `rawValue` string.
    static let cueInSwitchTab = Notification.Name("cuein.shell.switchTab")
}

// MARK: - Shell notification payloads

enum CueInShellNotification {
    /// `String` — ``AppTab/rawValue``.
    static let switchTabUserInfoKey = "cuein.shell.tab"
    /// `String` — ``UUID/uuidString`` for ``Notification.Name/cueInApplySavedFormula``.
    static let formulaIDUserInfoKey = "cuein.shell.formulaID"
}
