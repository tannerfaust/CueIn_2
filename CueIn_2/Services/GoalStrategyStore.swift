import Foundation
import Observation
import SwiftUI

// MARK: - Goal strategy projections

struct GoalProgressSummary {
    var completed: Int
    var total: Int
    var progress: Double
}

struct GoalResolvedWorkLink: Identifiable {
    let id: UUID
    let kind: GoalWorkLink.TargetKind
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let progress: Double?
    let isMissing: Bool
}

struct GoalNextMove {
    let title: String
    let detail: String
    let icon: String
    let tint: Color
}

// MARK: - GoalStrategyStore

@Observable
@MainActor
final class GoalStrategyStore {

    static let shared = GoalStrategyStore()

    private static let storageKey = "cuein.goalStrategy.goals.v1"

    var goals: [Goal] = [] {
        didSet { persist() }
    }

    private init() {
        if let stored = Self.loadStoredGoals() {
            goals = stored
        } else if CueInAppDataService.isGimmickDemoRemoved {
            goals = []
        } else {
            goals = Self.makeDemoSeed(tasksStore: TasksStore.shared)
        }
    }

    // MARK: - Goal lists

    var activeGoals: [Goal] {
        goals
            .filter { $0.status == .active || $0.status == .paused }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var completedGoals: [Goal] {
        goals
            .filter { $0.status == .completed }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func goal(_ id: UUID) -> Goal? {
        goals.first { $0.id == id }
    }

    // MARK: - Goal CRUD

    @discardableResult
    func addGoal(_ goal: Goal) -> UUID {
        goals.append(goal)
        return goal.id
    }

    @discardableResult
    func addGoal(from template: GoalTemplate) -> UUID {
        let now = Date()
        var stages = template.stages
        for index in stages.indices {
            stages[index].createdAt = now
            stages[index].updatedAt = now
        }

        let goal = Goal(
            title: template.title,
            why: template.why,
            iconName: template.iconName,
            colorHex: template.colorHex,
            stages: stages,
            canvas: template.canvas,
            createdAt: now,
            updatedAt: now
        )
        goals.append(goal)
        return goal.id
    }

    func updateGoal(_ goal: Goal) {
        guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        var next = goal
        next.updatedAt = Date()
        goals[index] = next
    }

    func deleteGoal(_ id: UUID) {
        goals.removeAll { $0.id == id }
    }

    func setGoalStatus(_ id: UUID, status: GoalStatus) {
        mutateGoal(id) { goal in
            goal.status = status
        }
    }

    // MARK: - Stage CRUD

    @discardableResult
    func addStage(goalID: UUID, title: String, summary: String = "", status: GoalStageStatus = .planned, targetDate: Date? = nil) -> UUID? {
        var createdID: UUID?
        mutateGoal(goalID) { goal in
            let stage = GoalStage(title: title, summary: summary, status: status, targetDate: targetDate)
            createdID = stage.id
            goal.stages.append(stage)
        }
        return createdID
    }

    func updateStage(goalID: UUID, stage: GoalStage) {
        mutateGoal(goalID) { goal in
            guard let index = goal.stages.firstIndex(where: { $0.id == stage.id }) else { return }
            var next = stage
            next.updatedAt = Date()
            goal.stages[index] = next
        }
    }

    func deleteStage(goalID: UUID, stageID: UUID) {
        mutateGoal(goalID) { goal in
            goal.stages.removeAll { $0.id == stageID }
        }
    }

    func setStageStatus(goalID: UUID, stageID: UUID, status: GoalStageStatus) {
        mutateGoal(goalID) { goal in
            guard let index = goal.stages.firstIndex(where: { $0.id == stageID }) else { return }
            goal.stages[index].status = status
            goal.stages[index].updatedAt = Date()
        }
    }

    func moveStage(goalID: UUID, stageID: UUID, direction: Int) {
        mutateGoal(goalID) { goal in
            guard let index = goal.stages.firstIndex(where: { $0.id == stageID }) else { return }
            let target = index + direction
            guard goal.stages.indices.contains(target) else { return }
            let item = goal.stages.remove(at: index)
            goal.stages.insert(item, at: target)
        }
    }

    // MARK: - Subgoal CRUD

    @discardableResult
    func addSubgoal(
        goalID: UUID,
        stageID: UUID,
        title: String,
        notes: String = "",
        status: GoalSubgoalStatus = .open,
        targetDate: Date? = nil,
        manualProgress: Double = 0
    ) -> UUID? {
        var createdID: UUID?
        mutateGoal(goalID) { goal in
            guard let stageIndex = goal.stages.firstIndex(where: { $0.id == stageID }) else { return }
            let subgoal = GoalSubgoal(
                title: title,
                notes: notes,
                status: status,
                targetDate: targetDate,
                manualProgress: manualProgress
            )
            createdID = subgoal.id
            goal.stages[stageIndex].subgoals.append(subgoal)
            goal.stages[stageIndex].updatedAt = Date()
        }
        return createdID
    }

    func updateSubgoal(goalID: UUID, stageID: UUID, subgoal: GoalSubgoal) {
        mutateGoal(goalID) { goal in
            guard let stageIndex = goal.stages.firstIndex(where: { $0.id == stageID }),
                  let subgoalIndex = goal.stages[stageIndex].subgoals.firstIndex(where: { $0.id == subgoal.id })
            else { return }
            var next = subgoal
            next.manualProgress = min(max(next.manualProgress, 0), 1)
            next.updatedAt = Date()
            goal.stages[stageIndex].subgoals[subgoalIndex] = next
            goal.stages[stageIndex].updatedAt = Date()
        }
    }

    func deleteSubgoal(goalID: UUID, stageID: UUID, subgoalID: UUID) {
        mutateGoal(goalID) { goal in
            guard let stageIndex = goal.stages.firstIndex(where: { $0.id == stageID }) else { return }
            goal.stages[stageIndex].subgoals.removeAll { $0.id == subgoalID }
            goal.stages[stageIndex].updatedAt = Date()
        }
    }

    func setSubgoalStatus(goalID: UUID, stageID: UUID, subgoalID: UUID, status: GoalSubgoalStatus) {
        mutateSubgoal(goalID: goalID, stageID: stageID, subgoalID: subgoalID) { subgoal in
            subgoal.status = status
        }
    }

    func setSubgoalManualProgress(goalID: UUID, stageID: UUID, subgoalID: UUID, progress: Double) {
        mutateSubgoal(goalID: goalID, stageID: stageID, subgoalID: subgoalID) { subgoal in
            subgoal.manualProgress = min(max(progress, 0), 1)
        }
    }

    // MARK: - Work links

    func addWorkLink(goalID: UUID, stageID: UUID, subgoalID: UUID, link: GoalWorkLink) {
        mutateSubgoal(goalID: goalID, stageID: stageID, subgoalID: subgoalID) { subgoal in
            guard !subgoal.linkedWork.contains(where: {
                $0.targetKind == link.targetKind && $0.targetID == link.targetID
            }) else { return }
            subgoal.linkedWork.append(link)
        }
    }

    func removeWorkLink(goalID: UUID, stageID: UUID, subgoalID: UUID, linkID: UUID) {
        mutateSubgoal(goalID: goalID, stageID: stageID, subgoalID: subgoalID) { subgoal in
            subgoal.linkedWork.removeAll { $0.id == linkID }
        }
    }

    @discardableResult
    func createLinkedTask(goalID: UUID, stageID: UUID, subgoalID: UUID, tasksStore: TasksStore) -> UUID? {
        guard let subgoal = findSubgoal(goalID: goalID, stageID: stageID, subgoalID: subgoalID) else { return nil }
        let task = TaskItem(
            title: subgoal.title,
            notes: subgoal.notes.isEmpty ? "Created from a goal subgoal." : subgoal.notes,
            priority: .high,
            status: .inbox
        )
        tasksStore.addTask(task)
        addWorkLink(
            goalID: goalID,
            stageID: stageID,
            subgoalID: subgoalID,
            link: GoalWorkLink(targetKind: .task, targetID: task.id, titleSnapshot: task.title)
        )
        return task.id
    }

    // MARK: - Canvas and reviews

    func updateCanvasValue(goalID: UUID, section: GoalCanvasSection, value: String) {
        mutateGoal(goalID) { goal in
            goal.canvas.setValue(value, for: section)
        }
    }

    func addReviewEntry(goalID: UUID, entry: GoalReviewEntry) {
        mutateGoal(goalID) { goal in
            goal.reviewEntries.insert(entry, at: 0)
        }
    }

    // MARK: - Progress

    func progress(goal: Goal, tasksStore: TasksStore) -> Double {
        if goal.status == .completed { return 1 }
        let meaningfulStages = goal.stages.filter { $0.status != .skipped }
        guard !meaningfulStages.isEmpty else { return 0 }
        let total = meaningfulStages.reduce(0) { $0 + progress(stage: $1, tasksStore: tasksStore) }
        return total / Double(meaningfulStages.count)
    }

    func progress(stage: GoalStage, tasksStore: TasksStore) -> Double {
        if stage.status == .completed { return 1 }
        if stage.status == .skipped { return 1 }
        let meaningfulSubgoals = stage.subgoals.filter { $0.status != .skipped }
        guard !meaningfulSubgoals.isEmpty else { return 0 }
        let total = meaningfulSubgoals.reduce(0) { $0 + progress(subgoal: $1, tasksStore: tasksStore) }
        return total / Double(meaningfulSubgoals.count)
    }

    func progress(subgoal: GoalSubgoal, tasksStore: TasksStore) -> Double {
        if subgoal.status == .completed { return 1 }
        if subgoal.status == .skipped { return 1 }
        let linkProgress = subgoal.linkedWork.compactMap { progress(link: $0, tasksStore: tasksStore) }
        guard !linkProgress.isEmpty else { return subgoal.manualProgress }
        return linkProgress.reduce(0, +) / Double(linkProgress.count)
    }

    func progressSummary(goal: Goal, tasksStore: TasksStore) -> GoalProgressSummary {
        let subgoals = goal.stages.flatMap(\.subgoals).filter { $0.status != .skipped }
        guard !subgoals.isEmpty else {
            return GoalProgressSummary(completed: goal.status == .completed ? 1 : 0, total: goal.status == .completed ? 1 : 0, progress: progress(goal: goal, tasksStore: tasksStore))
        }
        let completed = subgoals.filter { progress(subgoal: $0, tasksStore: tasksStore) >= 0.999 }.count
        return GoalProgressSummary(completed: completed, total: subgoals.count, progress: progress(goal: goal, tasksStore: tasksStore))
    }

    func currentStage(for goal: Goal) -> GoalStage? {
        goal.stages.first { $0.status == .active }
            ?? goal.stages.first { $0.status != .completed && $0.status != .skipped }
            ?? goal.stages.last
    }

    // MARK: - Strategic signals

    func nextMove(for goal: Goal, tasksStore: TasksStore) -> GoalNextMove {
        guard goal.status != .completed else {
            return GoalNextMove(
                title: "Goal completed",
                detail: "Review what worked and archive it when you are ready.",
                icon: "checkmark.seal.fill",
                tint: CueInColors.success
            )
        }

        guard let stage = currentStage(for: goal) else {
            return GoalNextMove(
                title: "Add the first stage",
                detail: "Give this goal a first phase so it can turn into action.",
                icon: "plus.circle.fill",
                tint: goal.color
            )
        }

        if stage.subgoals.isEmpty {
            return GoalNextMove(
                title: "Add a subgoal to \(stage.title)",
                detail: "Create the first concrete outcome for the current stage.",
                icon: "square.badge.plus",
                tint: goal.color
            )
        }

        let candidates = stage.subgoals.filter { $0.status != .completed && $0.status != .skipped }
        if let linkedTask = candidates
            .flatMap(\.linkedWork)
            .compactMap({ link -> TaskItem? in
                guard link.targetKind == .task else { return nil }
                return tasksStore.tasks.first { $0.id == link.targetID && !$0.isCompleted && $0.status != .archived }
            })
            .sorted(by: { $0.priority.sortWeight < $1.priority.sortWeight })
            .first {
            return GoalNextMove(
                title: linkedTask.title,
                detail: "Next task from \(stage.title)",
                icon: "bolt.fill",
                tint: goal.color
            )
        }

        if let unlinked = candidates.first(where: { $0.linkedWork.isEmpty }) {
            return GoalNextMove(
                title: unlinked.title,
                detail: "Link work or create the first action for this subgoal.",
                icon: "link.badge.plus",
                tint: goal.color
            )
        }

        if let first = candidates.first {
            return GoalNextMove(
                title: first.title,
                detail: "Move this subgoal forward inside \(stage.title).",
                icon: "arrow.up.right.circle.fill",
                tint: goal.color
            )
        }

        return GoalNextMove(
            title: "Review the roadmap",
            detail: "The current stage looks clear. Pick the next stage or complete the goal.",
            icon: "map.fill",
            tint: goal.color
        )
    }

    func staleSubgoals(for goal: Goal, tasksStore: TasksStore, olderThanDays: Int = 10) -> [(stage: GoalStage, subgoal: GoalSubgoal)] {
        let threshold = Calendar.current.date(byAdding: .day, value: -olderThanDays, to: Date()) ?? Date()
        var stale: [(GoalStage, GoalSubgoal)] = []
        for stage in goal.stages where stage.status != .completed && stage.status != .skipped {
            for subgoal in stage.subgoals where subgoal.status != .completed && subgoal.status != .skipped {
                if latestActivityDate(for: subgoal, tasksStore: tasksStore) < threshold {
                    stale.append((stage, subgoal))
                }
            }
        }
        return stale
    }

    func resolvedLink(_ link: GoalWorkLink, tasksStore: TasksStore) -> GoalResolvedWorkLink {
        switch link.targetKind {
        case .field:
            if let field = tasksStore.field(link.targetID) {
                let progress = progress(link: link, tasksStore: tasksStore)
                return GoalResolvedWorkLink(
                    id: link.id,
                    kind: .field,
                    title: field.name,
                    subtitle: "Initiative",
                    icon: field.resolvedIconSystemName,
                    tint: field.color,
                    progress: progress,
                    isMissing: false
                )
            }
        case .project:
            if let project = tasksStore.project(link.targetID) {
                let fieldName = tasksStore.field(project.fieldID)?.name ?? "Project"
                return GoalResolvedWorkLink(
                    id: link.id,
                    kind: .project,
                    title: project.name,
                    subtitle: fieldName,
                    icon: project.resolvedIconSystemName,
                    tint: tasksStore.color(for: project),
                    progress: progress(link: link, tasksStore: tasksStore),
                    isMissing: false
                )
            }
        case .task:
            if let task = tasksStore.tasks.first(where: { $0.id == link.targetID }) {
                let subtitle = task.isCompleted ? "Task done" : "Task"
                return GoalResolvedWorkLink(
                    id: link.id,
                    kind: .task,
                    title: task.title,
                    subtitle: subtitle,
                    icon: tasksStore.iconName(for: task),
                    tint: tasksStore.color(for: task),
                    progress: progress(link: link, tasksStore: tasksStore),
                    isMissing: false
                )
            }
        }

        return GoalResolvedWorkLink(
            id: link.id,
            kind: link.targetKind,
            title: link.titleSnapshot,
            subtitle: "Missing \(link.targetKind.label.lowercased())",
            icon: "exclamationmark.triangle.fill",
            tint: CueInColors.warning,
            progress: nil,
            isMissing: true
        )
    }

    // MARK: - AI-ready snapshot

    func strategySnapshot() -> [[String: Any]] {
        strategySnapshot(tasksStore: TasksStore.shared)
    }

    func strategySnapshot(tasksStore: TasksStore) -> [[String: Any]] {
        goals.map { goal in
            [
                "id": goal.id.uuidString,
                "title": goal.title,
                "why": goal.why,
                "status": goal.status.rawValue,
                "targetDate": goal.targetDate.map { ISO8601DateFormatter().string(from: $0) } as Any,
                "progress": progress(goal: goal, tasksStore: tasksStore),
                "nextMove": [
                    "title": nextMove(for: goal, tasksStore: tasksStore).title,
                    "detail": nextMove(for: goal, tasksStore: tasksStore).detail,
                ],
                "canvas": Dictionary(uniqueKeysWithValues: GoalCanvasSection.allCases.map {
                    ($0.rawValue, goal.canvas.value(for: $0))
                }),
                "stages": goal.stages.map { stage in
                    [
                        "id": stage.id.uuidString,
                        "title": stage.title,
                        "status": stage.status.rawValue,
                        "progress": progress(stage: stage, tasksStore: tasksStore),
                        "subgoals": stage.subgoals.map { subgoal in
                            [
                                "id": subgoal.id.uuidString,
                                "title": subgoal.title,
                                "status": subgoal.status.rawValue,
                                "progress": progress(subgoal: subgoal, tasksStore: tasksStore),
                                "linkedWork": subgoal.linkedWork.map { link in
                                    [
                                        "kind": link.targetKind.rawValue,
                                        "id": link.targetID.uuidString,
                                        "title": resolvedLink(link, tasksStore: tasksStore).title,
                                    ]
                                },
                            ] as [String: Any]
                        },
                    ] as [String: Any]
                },
            ] as [String: Any]
        }
    }

    // MARK: - Reset and seed

    func replaceWithGimmickSeed() {
        goals = Self.makeDemoSeed(tasksStore: TasksStore.shared)
    }

    func clearAllGoalsData() {
        goals = []
    }

    // MARK: - Private helpers

    private func mutateGoal(_ goalID: UUID, _ mutation: (inout Goal) -> Void) {
        guard let index = goals.firstIndex(where: { $0.id == goalID }) else { return }
        mutation(&goals[index])
        goals[index].updatedAt = Date()
    }

    private func mutateSubgoal(goalID: UUID, stageID: UUID, subgoalID: UUID, _ mutation: (inout GoalSubgoal) -> Void) {
        mutateGoal(goalID) { goal in
            guard let stageIndex = goal.stages.firstIndex(where: { $0.id == stageID }),
                  let subgoalIndex = goal.stages[stageIndex].subgoals.firstIndex(where: { $0.id == subgoalID })
            else { return }
            mutation(&goal.stages[stageIndex].subgoals[subgoalIndex])
            goal.stages[stageIndex].subgoals[subgoalIndex].updatedAt = Date()
            goal.stages[stageIndex].updatedAt = Date()
        }
    }

    private func findSubgoal(goalID: UUID, stageID: UUID, subgoalID: UUID) -> GoalSubgoal? {
        goal(goalID)?
            .stages.first { $0.id == stageID }?
            .subgoals.first { $0.id == subgoalID }
    }

    private func progress(link: GoalWorkLink, tasksStore: TasksStore) -> Double? {
        switch link.targetKind {
        case .field:
            guard let field = tasksStore.field(link.targetID) else { return nil }
            let stats = tasksStore.progress(field: field)
            guard stats.total > 0 else { return 0 }
            return Double(stats.done) / Double(stats.total)
        case .project:
            guard let project = tasksStore.project(link.targetID) else { return nil }
            let stats = tasksStore.progress(project: project)
            guard stats.total > 0 else { return project.status == .done ? 1 : 0 }
            return Double(stats.done) / Double(stats.total)
        case .task:
            guard let task = tasksStore.tasks.first(where: { $0.id == link.targetID }) else { return nil }
            return task.isCompleted ? 1 : 0
        }
    }

    private func latestActivityDate(for subgoal: GoalSubgoal, tasksStore: TasksStore) -> Date {
        var latest = subgoal.updatedAt
        for link in subgoal.linkedWork {
            switch link.targetKind {
            case .field:
                let dates = tasksStore.tasks(in: link.targetID).map(\.updatedAt)
                latest = max(latest, dates.max() ?? latest)
            case .project:
                let dates = tasksStore.tasksInProject(link.targetID).map(\.updatedAt)
                latest = max(latest, dates.max() ?? latest)
            case .task:
                if let task = tasksStore.tasks.first(where: { $0.id == link.targetID }) {
                    latest = max(latest, task.updatedAt)
                    if let completedAt = task.completedAt {
                        latest = max(latest, completedAt)
                    }
                }
            }
        }
        return latest
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(goals) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
        CueInSyncRuntimeBridge.shared.recordGoalsSnapshot(goals)
    }

    private static func loadStoredGoals() -> [Goal]? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode([Goal].self, from: data)
    }

    private static func makeDemoSeed(tasksStore: TasksStore) -> [Goal] {
        let cueInField = tasksStore.fields.first { $0.name == "CueIn" }
        let productProject = tasksStore.projects.first { $0.name.localizedCaseInsensitiveContains("iOS") }
        let trainingProject = tasksStore.projects.first { $0.name.localizedCaseInsensitiveContains("Training") }
        let roadmapTask = tasksStore.tasks.first { $0.title.localizedCaseInsensitiveContains("roadmap") }
        let stepsTask = tasksStore.tasks.first { $0.title.localizedCaseInsensitiveContains("10k") }

        func link(kind: GoalWorkLink.TargetKind, id: UUID?, title: String) -> [GoalWorkLink] {
            guard let id else { return [] }
            return [GoalWorkLink(targetKind: kind, targetID: id, titleSnapshot: title)]
        }

        let shipCueIn = Goal(
            title: "Ship CueIn v1",
            why: "Turn the product into a real operating system for daily execution.",
            successMetric: "A usable v1 with a coherent Today, Tasks, Hub, and strategy loop.",
            notes: "Keep scope tight: the goal is a useful first system, not a bloated workspace.",
            iconName: "paperplane.fill",
            colorHex: 0x34C759,
            targetDate: Calendar.current.date(byAdding: .month, value: 3, to: Date()),
            stages: [
                GoalStage(
                    title: "Foundation",
                    summary: "Make the core system reliable.",
                    status: .active,
                    subgoals: [
                        GoalSubgoal(
                            title: "Connect strategy to the real work layer",
                            status: .active,
                            linkedWork: link(kind: .field, id: cueInField?.id, title: cueInField?.name ?? "CueIn")
                        ),
                        GoalSubgoal(
                            title: "Lock the product roadmap",
                            status: .open,
                            linkedWork: link(kind: .task, id: roadmapTask?.id, title: roadmapTask?.title ?? "Plan roadmap")
                        )
                    ]
                ),
                GoalStage(
                    title: "Build",
                    summary: "Ship the product surfaces that make the loop useful.",
                    subgoals: [
                        GoalSubgoal(
                            title: "Finish the iOS app experience",
                            linkedWork: link(kind: .project, id: productProject?.id, title: productProject?.name ?? "iOS app")
                        )
                    ]
                ),
                GoalStage(title: "Launch", summary: "Put the app in front of real users.")
            ],
            canvas: GoalCanvas(
                outcome: "CueIn v1 helps a person turn direction into daily action.",
                why: "The product should reduce chaos and make ambition executable.",
                currentReality: "The execution and task layers exist; strategy needs to connect them.",
                keyLevers: "Scope control, daily shipping, strong UX, real progress loops.",
                risks: "Overbuilding planning surfaces instead of making them actionable.",
                weeklyCommitment: "Protect deep work blocks and review the roadmap every week.",
                definitionOfDone: "A user can set a goal, break it down, link work, and act today."
            )
        )

        let healthGoal = Goal(
            title: "Build a stronger baseline",
            why: "Better energy makes the rest of the system easier to execute.",
            successMetric: "Consistent training, sleep, and daily movement.",
            iconName: "heart.fill",
            colorHex: 0x5BC6B9,
            targetDate: Calendar.current.date(byAdding: .month, value: 2, to: Date()),
            stages: [
                GoalStage(
                    title: "Rhythm",
                    summary: "Make health behavior repeatable.",
                    status: .active,
                    subgoals: [
                        GoalSubgoal(
                            title: "Keep the weekly movement floor",
                            status: .active,
                            linkedWork: link(kind: .project, id: trainingProject?.id, title: trainingProject?.name ?? "Training")
                                + link(kind: .task, id: stepsTask?.id, title: stepsTask?.title ?? "Hit 10k steps")
                        )
                    ]
                ),
                GoalStage(title: "Capacity", summary: "Increase the standard once the rhythm holds.")
            ],
            canvas: GoalCanvas(
                outcome: "A body and routine that support high-output days.",
                why: "Health is a multiplier for focus, mood, and consistency.",
                currentReality: "Movement is present, but needs a clearer repeatable system.",
                keyLevers: "Steps, training, recovery, nutrition.",
                weeklyCommitment: "Three training sessions and daily baseline movement.",
                definitionOfDone: "The routine holds for four straight weeks."
            )
        )

        return [shipCueIn, healthGoal]
    }
}
