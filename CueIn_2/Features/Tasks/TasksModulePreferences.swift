import Foundation

// MARK: - TasksModulePreferences

enum TasksModulePreferences {
    /// When false, Notion-imported tasks only appear under the Notion sidebar section.
    static let showNotionInCueInListsKey = "cuein.tasks.notion.showInCueInLists"
    /// When false, Linear-imported tasks only appear under the Linear sidebar section.
    static let showLinearInCueInListsKey = "cuein.tasks.linear.showInCueInLists"

    static var showNotionInCueInLists: Bool {
        if UserDefaults.standard.object(forKey: showNotionInCueInListsKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: showNotionInCueInListsKey)
    }

    static var showLinearInCueInLists: Bool {
        if UserDefaults.standard.object(forKey: showLinearInCueInListsKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: showLinearInCueInListsKey)
    }

    static func shouldShowTaskInCueInLists(_ task: TaskItem) -> Bool {
        if task.isNotionImported {
            return showNotionInCueInLists
        }
        if task.isLinearImported {
            return showLinearInCueInLists
        }
        return true
    }
}
