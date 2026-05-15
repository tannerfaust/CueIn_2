import Foundation

enum GoalStrategyRoute: Hashable {
    case home
    case goal(UUID)
}

enum GoalStrategySheet: Identifiable, Hashable {
    case createGoal(templateID: String?)
    case editGoal(UUID)
    case createStage(goalID: UUID)
    case editStage(goalID: UUID, stageID: UUID)
    case createSubgoal(goalID: UUID, stageID: UUID)
    case editSubgoal(goalID: UUID, stageID: UUID, subgoalID: UUID)
    case linkWork(goalID: UUID, stageID: UUID, subgoalID: UUID)
    case review(goalID: UUID)

    var id: String {
        switch self {
        case .createGoal(let templateID):
            return "createGoal:\(templateID ?? "blank")"
        case .editGoal(let id):
            return "editGoal:\(id.uuidString)"
        case .createStage(let goalID):
            return "createStage:\(goalID.uuidString)"
        case .editStage(let goalID, let stageID):
            return "editStage:\(goalID.uuidString):\(stageID.uuidString)"
        case .createSubgoal(let goalID, let stageID):
            return "createSubgoal:\(goalID.uuidString):\(stageID.uuidString)"
        case .editSubgoal(let goalID, let stageID, let subgoalID):
            return "editSubgoal:\(goalID.uuidString):\(stageID.uuidString):\(subgoalID.uuidString)"
        case .linkWork(let goalID, let stageID, let subgoalID):
            return "linkWork:\(goalID.uuidString):\(stageID.uuidString):\(subgoalID.uuidString)"
        case .review(let goalID):
            return "review:\(goalID.uuidString)"
        }
    }
}

extension Notification.Name {
    static let cueInShowCreateGoal = Notification.Name("cueInShowCreateGoal")
}
