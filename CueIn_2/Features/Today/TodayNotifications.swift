import Foundation

extension Notification.Name {
    static let cueInShowTodayFormulaPicker = Notification.Name("cuein.today.showFormulaPicker")
    static let cueInShowScheduleStartSetup = Notification.Name("cuein.today.showScheduleStartSetup")
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
}
