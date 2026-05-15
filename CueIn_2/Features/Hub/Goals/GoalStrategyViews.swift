import SwiftUI

// MARK: - Goals Home

struct GoalsHomeView: View {
    let store: GoalStrategyStore
    let tasksStore: TasksStore
    let onCreateGoal: (GoalTemplate?) -> Void
    let onPresentSheet: (GoalStrategySheet) -> Void

    @State private var selectedGoalID: UUID?
    @State private var mode: StrategyStudioMode = .map

    private var visibleGoals: [Goal] {
        let active = store.activeGoals
        return active.isEmpty ? store.completedGoals : active
    }

    private var selectedGoal: Goal? {
        if let selectedGoalID, let selected = visibleGoals.first(where: { $0.id == selectedGoalID }) {
            return selected
        }
        return visibleGoals.first
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: CueInSpacing.xl) {
                studioHeader

                if visibleGoals.isEmpty {
                    EmptyStrategyStudio(onCreateGoal: onCreateGoal)
                } else {
                    goalRail
                    if let selectedGoal {
                        StrategyWorkspace(
                            goal: selectedGoal,
                            store: store,
                            tasksStore: tasksStore,
                            mode: $mode,
                            onPresentSheet: onPresentSheet
                        )
                    }
                }
            }
            .padding(.horizontal, CueInSpacing.screenHorizontal)
            .padding(.top, CueInSpacing.base)
            .padding(.bottom, CueInLayout.scrollBottomInset)
        }
        .background(CueInColors.background.ignoresSafeArea())
        .navigationTitle("Strategy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { onCreateGoal(nil) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(CueInColors.accentFocus)
                .accessibilityLabel("New goal")
            }
        }
        .onAppear { keepSelectionValid() }
        .onChange(of: visibleGoals.map(\.id)) { _, _ in keepSelectionValid() }
    }

    private var studioHeader: some View {
        HStack(alignment: .center, spacing: CueInSpacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Strategy")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(CueInColors.textPrimary)
                Text("Map the direction. Turn it into work.")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
            }
            Spacer()
            Button { onCreateGoal(nil) } label: {
                Image(systemName: "target")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CueInColors.textPrimary)
                    .frame(width: 46, height: 46)
                    .background(CueInColors.surfacePrimary, in: Circle())
                    .overlay(Circle().strokeBorder(CueInColors.cardBorder, lineWidth: 0.6))
            }
            .buttonStyle(.plain)
        }
    }

    private var goalRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CueInSpacing.sm) {
                ForEach(visibleGoals) { goal in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedGoalID = goal.id
                        }
                    } label: {
                        GoalRailChip(
                            goal: goal,
                            progress: store.progress(goal: goal, tasksStore: tasksStore),
                            selected: selectedGoal?.id == goal.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.trailing, CueInSpacing.screenHorizontal)
        }
    }

    private func keepSelectionValid() {
        guard !visibleGoals.isEmpty else {
            selectedGoalID = nil
            return
        }
        if selectedGoalID == nil || !visibleGoals.contains(where: { $0.id == selectedGoalID }) {
            selectedGoalID = visibleGoals.first?.id
        }
    }
}

// MARK: - Goal Detail

struct GoalDetailView: View {
    let goalID: UUID
    let store: GoalStrategyStore
    let tasksStore: TasksStore
    let onPresentSheet: (GoalStrategySheet) -> Void

    @State private var mode: StrategyStudioMode = .map
    @Environment(\.dismiss) private var dismiss

    private var goal: Goal? { store.goal(goalID) }

    var body: some View {
        Group {
            if let goal {
                ScrollView(.vertical, showsIndicators: false) {
                    StrategyWorkspace(
                        goal: goal,
                        store: store,
                        tasksStore: tasksStore,
                        mode: $mode,
                        onPresentSheet: onPresentSheet
                    )
                    .padding(.horizontal, CueInSpacing.screenHorizontal)
                    .padding(.top, CueInSpacing.base)
                    .padding(.bottom, CueInLayout.scrollBottomInset)
                }
                .background(CueInColors.background.ignoresSafeArea())
                .navigationTitle(goal.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button { onPresentSheet(.editGoal(goal.id)) } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button {
                                store.setGoalStatus(goal.id, status: goal.status == .paused ? .active : .paused)
                            } label: {
                                Label(goal.status == .paused ? "Resume" : "Pause", systemImage: goal.status == .paused ? "play.circle" : "pause.circle")
                            }
                            Button { store.setGoalStatus(goal.id, status: .completed) } label: {
                                Label("Complete", systemImage: "checkmark.circle")
                            }
                            Divider()
                            Button(role: .destructive) {
                                store.deleteGoal(goal.id)
                                dismiss()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .foregroundStyle(CueInColors.textSecondary)
                    }
                }
            } else {
                StrategyMissingView()
            }
        }
    }
}

// MARK: - Strategy Workspace

private enum StrategyStudioMode: String, CaseIterable, Identifiable {
    case map = "Map"
    case roadmap = "Roadmap"
    case canvas = "Canvas"
    case review = "Review"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .map: return "point.3.connected.trianglepath.dotted"
        case .roadmap: return "map.fill"
        case .canvas: return "square.grid.2x2"
        case .review: return "arrow.triangle.2.circlepath"
        }
    }
}

private struct StrategyWorkspace: View {
    let goal: Goal
    let store: GoalStrategyStore
    let tasksStore: TasksStore
    @Binding var mode: StrategyStudioMode
    let onPresentSheet: (GoalStrategySheet) -> Void

    private var currentStage: GoalStage? { store.currentStage(for: goal) }
    private var focusSubgoal: GoalSubgoal? {
        currentStage?.subgoals.first { $0.status == .active }
            ?? currentStage?.subgoals.first { $0.status != .completed && $0.status != .skipped }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.lg) {
            StrategyHeader(goal: goal, store: store, tasksStore: tasksStore)
            StrategyModeBar(mode: $mode)
            StrategyToolDock(
                goal: goal,
                stage: currentStage,
                subgoal: focusSubgoal,
                store: store,
                tasksStore: tasksStore,
                onPresentSheet: onPresentSheet
            )

            switch mode {
            case .map:
                StrategyMapSurface(
                    goal: goal,
                    store: store,
                    tasksStore: tasksStore,
                    onShowCanvas: { mode = .canvas },
                    onShowReview: { mode = .review },
                    onPresentSheet: onPresentSheet
                )
            case .roadmap:
                RoadmapBoard(goal: goal, store: store, tasksStore: tasksStore, onPresentSheet: onPresentSheet)
            case .canvas:
                StrategyCanvasBoard(goal: goal, store: store)
            case .review:
                StrategyReviewBoard(goal: goal, store: store, tasksStore: tasksStore, onPresentSheet: onPresentSheet)
            }
        }
    }
}

// MARK: - Map

private struct StrategyMapSurface: View {
    let goal: Goal
    let store: GoalStrategyStore
    let tasksStore: TasksStore
    let onShowCanvas: () -> Void
    let onShowReview: () -> Void
    let onPresentSheet: (GoalStrategySheet) -> Void

    private var currentStage: GoalStage? { store.currentStage(for: goal) }
    private var nowSubgoals: [GoalSubgoal] {
        currentStage?.subgoals.filter { $0.status != .completed && $0.status != .skipped } ?? []
    }
    private var nextStage: GoalStage? {
        guard let currentStage,
              let index = goal.stages.firstIndex(where: { $0.id == currentStage.id })
        else { return goal.stages.first }
        return goal.stages.dropFirst(index + 1).first { $0.status != .skipped }
    }
    private var laterCount: Int {
        guard let nextStage,
              let index = goal.stages.firstIndex(where: { $0.id == nextStage.id })
        else { return max(0, goal.stages.count - 1) }
        return max(0, goal.stages.count - index - 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.lg) {
            ZStack {
                StrategyMapLines()
                    .allowsHitTesting(false)

                VStack(spacing: CueInSpacing.lg) {
                    StrategyNode(
                        title: goal.title,
                        subtitle: goal.successMetric.isEmpty ? goal.status.label : goal.successMetric,
                        icon: goal.resolvedIconSystemName,
                        tint: goal.color,
                        style: .hero
                    )

                    if let currentStage {
                        StrategyNode(
                            title: currentStage.title,
                            subtitle: "\(Int(store.progress(stage: currentStage, tasksStore: tasksStore) * 100))% current stage",
                            icon: currentStage.status.icon,
                            tint: currentStage.status.tint,
                            style: .stage
                        )
                    } else {
                        Button {
                            onPresentSheet(.createStage(goalID: goal.id))
                        } label: {
                            StrategyNode(
                                title: "Add first stage",
                                subtitle: "Create the first phase",
                                icon: "plus.circle.fill",
                                tint: goal.color,
                                style: .stage
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(alignment: .top, spacing: CueInSpacing.sm) {
                        StrategyLaneNode(
                            title: "Now",
                            subtitle: nowSubgoals.first?.title ?? "Choose focus",
                            value: "\(nowSubgoals.count)",
                            tint: goal.color
                        )
                        StrategyLaneNode(
                            title: "Next",
                            subtitle: nextStage?.title ?? "No next stage",
                            value: nextStage.map { "\(Int(store.progress(stage: $0, tasksStore: tasksStore) * 100))%" } ?? "--",
                            tint: CueInColors.accentMini
                        )
                        StrategyLaneNode(
                            title: "Later",
                            subtitle: laterCount == 0 ? "No backlog" : "Stages waiting",
                            value: "\(laterCount)",
                            tint: CueInColors.textSecondary
                        )
                    }
                }
            }
            .padding(.vertical, CueInSpacing.md)

            StrategyToolGrid(
                goal: goal,
                store: store,
                tasksStore: tasksStore,
                onShowCanvas: onShowCanvas,
                onShowReview: onShowReview
            )
        }
    }
}

private struct StrategyMapLines: View {
    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                var path = Path()
                let centerX = size.width / 2
                path.move(to: CGPoint(x: centerX, y: 78))
                path.addLine(to: CGPoint(x: centerX, y: 178))
                path.move(to: CGPoint(x: centerX, y: 178))
                path.addLine(to: CGPoint(x: size.width * 0.17, y: 254))
                path.move(to: CGPoint(x: centerX, y: 178))
                path.addLine(to: CGPoint(x: centerX, y: 254))
                path.move(to: CGPoint(x: centerX, y: 178))
                path.addLine(to: CGPoint(x: size.width * 0.83, y: 254))
                context.stroke(path, with: .color(CueInColors.divider), lineWidth: 1.2)
            }
            .frame(width: proxy.size.width, height: 310)
        }
        .frame(height: 310)
    }
}

// MARK: - Roadmap

private struct RoadmapBoard: View {
    let goal: Goal
    let store: GoalStrategyStore
    let tasksStore: TasksStore
    let onPresentSheet: (GoalStrategySheet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            HStack {
                StrategySectionTitle("Roadmap")
                Spacer()
                Button { onPresentSheet(.createStage(goalID: goal.id)) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CueInColors.textPrimary)
                        .frame(width: 32, height: 32)
                        .background(CueInColors.surfacePrimary, in: Circle())
                        .overlay(Circle().strokeBorder(CueInColors.cardBorder, lineWidth: 0.6))
                }
                .buttonStyle(.plain)
            }

            if goal.stages.isEmpty {
                StrategyEmptyState(icon: "map", title: "No route yet", actionTitle: "Add stage") {
                    onPresentSheet(.createStage(goalID: goal.id))
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: CueInSpacing.md) {
                        ForEach(Array(goal.stages.enumerated()), id: \.element.id) { index, stage in
                            RoadmapStageColumn(
                                goal: goal,
                                stage: stage,
                                index: index,
                                isLast: index == goal.stages.count - 1,
                                store: store,
                                tasksStore: tasksStore,
                                onPresentSheet: onPresentSheet
                            )
                        }
                    }
                    .padding(.trailing, CueInSpacing.screenHorizontal)
                }
            }
        }
    }
}

private struct RoadmapStageColumn: View {
    let goal: Goal
    let stage: GoalStage
    let index: Int
    let isLast: Bool
    let store: GoalStrategyStore
    let tasksStore: TasksStore
    let onPresentSheet: (GoalStrategySheet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            HStack(spacing: 0) {
                Circle()
                    .fill(stage.status.tint)
                    .frame(width: 12, height: 12)
                if !isLast {
                    Rectangle()
                        .fill(stage.status.tint.opacity(0.35))
                        .frame(width: 208, height: 2)
                }
            }
            .padding(.leading, 4)

            VStack(alignment: .leading, spacing: CueInSpacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stage.title)
                            .font(CueInTypography.headline)
                            .foregroundStyle(CueInColors.textPrimary)
                            .lineLimit(2)
                        Text(stage.status.label)
                            .font(CueInTypography.micro)
                            .foregroundStyle(stage.status.tint)
                    }
                    Spacer()
                    stageMenu
                }

                ProgressView(value: store.progress(stage: stage, tasksStore: tasksStore))
                    .tint(stage.status.tint)
                    .scaleEffect(x: 1, y: 0.7, anchor: .center)

                VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                    ForEach(stage.subgoals) { subgoal in
                        RoadmapSubgoalNode(
                            goal: goal,
                            stage: stage,
                            subgoal: subgoal,
                            store: store,
                            tasksStore: tasksStore,
                            onPresentSheet: onPresentSheet
                        )
                    }

                    Button {
                        onPresentSheet(.createSubgoal(goalID: goal.id, stageID: stage.id))
                    } label: {
                        Label("Subgoal", systemImage: "plus")
                            .font(CueInTypography.micro)
                            .foregroundStyle(CueInColors.textSecondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .background(CueInColors.activeHint, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 220, alignment: .topLeading)
            .padding(CueInSpacing.md)
            .background(CueInColors.surfacePrimary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(stage.status.tint.opacity(0.18), lineWidth: 0.7)
            )
        }
    }

    private var stageMenu: some View {
        Menu {
            Button { onPresentSheet(.editStage(goalID: goal.id, stageID: stage.id)) } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button { onPresentSheet(.createSubgoal(goalID: goal.id, stageID: stage.id)) } label: {
                Label("Add subgoal", systemImage: "plus")
            }
            Divider()
            ForEach(GoalStageStatus.allCases) { status in
                Button { store.setStageStatus(goalID: goal.id, stageID: stage.id, status: status) } label: {
                    Label(status.label, systemImage: status.icon)
                }
            }
            Divider()
            Button { store.moveStage(goalID: goal.id, stageID: stage.id, direction: -1) } label: {
                Label("Move left", systemImage: "arrow.left")
            }
            .disabled(index == 0)
            Button { store.moveStage(goalID: goal.id, stageID: stage.id, direction: 1) } label: {
                Label("Move right", systemImage: "arrow.right")
            }
            .disabled(isLast)
            Divider()
            Button(role: .destructive) { store.deleteStage(goalID: goal.id, stageID: stage.id) } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CueInColors.textTertiary)
                .frame(width: 28, height: 28)
        }
    }
}

private struct RoadmapSubgoalNode: View {
    let goal: Goal
    let stage: GoalStage
    let subgoal: GoalSubgoal
    let store: GoalStrategyStore
    let tasksStore: TasksStore
    let onPresentSheet: (GoalStrategySheet) -> Void

    var body: some View {
        let progress = store.progress(subgoal: subgoal, tasksStore: tasksStore)

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: subgoal.status.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(subgoal.status.tint)
                    .frame(width: 18)
                Text(subgoal.title)
                    .font(CueInTypography.captionMedium)
                    .foregroundStyle(CueInColors.textPrimary)
                    .lineLimit(3)
                Spacer(minLength: 0)
                subgoalMenu
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(CueInColors.surfaceTertiary)
                    Capsule().fill(subgoal.status.tint).frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 4)

            if !subgoal.linkedWork.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                    Text("\(subgoal.linkedWork.count)")
                }
                .font(CueInTypography.micro)
                .foregroundStyle(CueInColors.textTertiary)
            }
        }
        .padding(CueInSpacing.sm)
        .background(CueInColors.surfaceSecondary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var subgoalMenu: some View {
        Menu {
            Button { onPresentSheet(.editSubgoal(goalID: goal.id, stageID: stage.id, subgoalID: subgoal.id)) } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button { onPresentSheet(.linkWork(goalID: goal.id, stageID: stage.id, subgoalID: subgoal.id)) } label: {
                Label("Link work", systemImage: "link")
            }
            Button { _ = store.createLinkedTask(goalID: goal.id, stageID: stage.id, subgoalID: subgoal.id, tasksStore: tasksStore) } label: {
                Label("Create task", systemImage: "checklist")
            }
            Divider()
            ForEach(GoalSubgoalStatus.allCases) { status in
                Button { store.setSubgoalStatus(goalID: goal.id, stageID: stage.id, subgoalID: subgoal.id, status: status) } label: {
                    Label(status.label, systemImage: status.icon)
                }
            }
            Divider()
            Button(role: .destructive) { store.deleteSubgoal(goalID: goal.id, stageID: stage.id, subgoalID: subgoal.id) } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CueInColors.textTertiary)
                .frame(width: 18, height: 18)
        }
    }
}

// MARK: - Canvas

private struct StrategyCanvasBoard: View {
    let goal: Goal
    let store: GoalStrategyStore

    private let sections: [GoalCanvasSection] = [
        .outcome, .currentReality, .keyLevers, .risks,
        .weeklyCommitment, .definitionOfDone, .constraints, .why
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            StrategySectionTitle("Strategy canvas")

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: CueInSpacing.sm), GridItem(.flexible(), spacing: CueInSpacing.sm)],
                spacing: CueInSpacing.sm
            ) {
                ForEach(sections) { section in
                    CanvasCell(goal: goal, section: section, store: store)
                }
            }
        }
    }
}

private struct CanvasCell: View {
    let goal: Goal
    let section: GoalCanvasSection
    let store: GoalStrategyStore

    private var text: Binding<String> {
        Binding(
            get: { store.goal(goal.id)?.canvas.value(for: section) ?? "" },
            set: { store.updateCanvasValue(goalID: goal.id, section: section, value: $0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: section.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(goal.color)
                Text(section.title)
                    .font(CueInTypography.micro)
                    .foregroundStyle(CueInColors.textSecondary)
                    .lineLimit(1)
            }

            TextEditor(text: text)
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textPrimary)
                .tint(goal.color)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 108)
                .padding(6)
                .background(CueInColors.background.opacity(0.35), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .padding(CueInSpacing.sm)
        .background(CueInColors.surfacePrimary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(CueInColors.cardBorder, lineWidth: 0.6)
        )
    }
}

// MARK: - Review

private struct StrategyReviewBoard: View {
    let goal: Goal
    let store: GoalStrategyStore
    let tasksStore: TasksStore
    let onPresentSheet: (GoalStrategySheet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            HStack {
                StrategySectionTitle("Review")
                Spacer()
                Button { onPresentSheet(.review(goalID: goal.id)) } label: {
                    Label("Check in", systemImage: "plus")
                        .font(CueInTypography.micro)
                        .foregroundStyle(CueInColors.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(CueInColors.surfacePrimary, in: Capsule())
                        .overlay(Capsule().strokeBorder(CueInColors.cardBorder, lineWidth: 0.6))
                }
                .buttonStyle(.plain)
            }

            let stale = store.staleSubgoals(for: goal, tasksStore: tasksStore)
            ReviewSignalStrip(goal: goal, staleCount: stale.count, reviewCount: goal.reviewEntries.count)

            if goal.reviewEntries.isEmpty {
                StrategyEmptyState(icon: "arrow.triangle.2.circlepath", title: "No check-ins", actionTitle: "Start") {
                    onPresentSheet(.review(goalID: goal.id))
                }
            } else {
                VStack(spacing: CueInSpacing.sm) {
                    ForEach(goal.reviewEntries.prefix(6)) { entry in
                        ReviewEntryRow(entry: entry)
                    }
                }
            }
        }
    }
}

// MARK: - Tools

private struct StrategyToolDock: View {
    let goal: Goal
    let stage: GoalStage?
    let subgoal: GoalSubgoal?
    let store: GoalStrategyStore
    let tasksStore: TasksStore
    let onPresentSheet: (GoalStrategySheet) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CueInSpacing.sm) {
                StrategyToolButton(icon: "plus.square.dashed", title: "Stage") {
                    onPresentSheet(.createStage(goalID: goal.id))
                }
                StrategyToolButton(icon: "target", title: "Subgoal") {
                    if let stage {
                        onPresentSheet(.createSubgoal(goalID: goal.id, stageID: stage.id))
                    } else {
                        onPresentSheet(.createStage(goalID: goal.id))
                    }
                }
                StrategyToolButton(icon: "link", title: "Link") {
                    if let stage, let subgoal {
                        onPresentSheet(.linkWork(goalID: goal.id, stageID: stage.id, subgoalID: subgoal.id))
                    } else if let stage {
                        onPresentSheet(.createSubgoal(goalID: goal.id, stageID: stage.id))
                    } else {
                        onPresentSheet(.createStage(goalID: goal.id))
                    }
                }
                StrategyToolButton(icon: "checklist", title: "Task") {
                    if let stage, let subgoal {
                        _ = store.createLinkedTask(goalID: goal.id, stageID: stage.id, subgoalID: subgoal.id, tasksStore: tasksStore)
                    } else if let stage {
                        onPresentSheet(.createSubgoal(goalID: goal.id, stageID: stage.id))
                    } else {
                        onPresentSheet(.createStage(goalID: goal.id))
                    }
                }
                StrategyToolButton(icon: "arrow.triangle.2.circlepath", title: "Review") {
                    onPresentSheet(.review(goalID: goal.id))
                }
                StrategyToolButton(icon: "sparkles", title: "Template") {
                    onPresentSheet(.createGoal(templateID: GoalTemplate.library.first?.id))
                }
            }
            .padding(.trailing, CueInSpacing.screenHorizontal)
        }
    }
}

private struct StrategyToolGrid: View {
    let goal: Goal
    let store: GoalStrategyStore
    let tasksStore: TasksStore
    let onShowCanvas: () -> Void
    let onShowReview: () -> Void

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: CueInSpacing.sm), GridItem(.flexible(), spacing: CueInSpacing.sm)],
            spacing: CueInSpacing.sm
        ) {
            Button(action: onShowCanvas) {
                StrategyInsightTile(
                    title: "Levers",
                    value: trimmed(goal.canvas.keyLevers, fallback: "Set the movers"),
                    icon: "slider.horizontal.3",
                    tint: goal.color
                )
            }
            .buttonStyle(.plain)

            Button(action: onShowCanvas) {
                StrategyInsightTile(
                    title: "Risks",
                    value: trimmed(goal.canvas.risks, fallback: "Name the blockers"),
                    icon: "exclamationmark.triangle.fill",
                    tint: CueInColors.warning
                )
            }
            .buttonStyle(.plain)

            Button(action: onShowReview) {
                let staleCount = store.staleSubgoals(for: goal, tasksStore: tasksStore).count
                StrategyInsightTile(
                    title: "Pressure",
                    value: staleCount == 0 ? "No stale work" : "\(staleCount) stalled",
                    icon: "gauge.with.dots.needle.bottom.50percent",
                    tint: staleCount == 0 ? CueInColors.success : CueInColors.warning
                )
            }
            .buttonStyle(.plain)

            Button(action: onShowCanvas) {
                StrategyInsightTile(
                    title: "Done means",
                    value: trimmed(goal.canvas.definitionOfDone, fallback: "Define proof"),
                    icon: "checkmark.seal.fill",
                    tint: CueInColors.success
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func trimmed(_ value: String, fallback: String) -> String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? fallback : clean
    }
}

// MARK: - Visual atoms

private struct StrategyHeader: View {
    let goal: Goal
    let store: GoalStrategyStore
    let tasksStore: TasksStore

    var body: some View {
        let progress = store.progress(goal: goal, tasksStore: tasksStore)
        let move = store.nextMove(for: goal, tasksStore: tasksStore)

        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            HStack(alignment: .top, spacing: CueInSpacing.md) {
                Image(systemName: goal.resolvedIconSystemName)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(goal.color)
                    .frame(width: 58, height: 58)
                    .background(goal.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(goal.title)
                        .font(CueInTypography.title)
                        .foregroundStyle(CueInColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        Image(systemName: move.icon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(move.tint)
                        Text(move.title)
                            .font(CueInTypography.caption)
                            .foregroundStyle(CueInColors.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Text("\(Int(progress * 100))%")
                    .font(CueInTypography.headline)
                    .foregroundStyle(CueInColors.textPrimary)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(CueInColors.surfaceTertiary)
                    Capsule().fill(goal.color).frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 5)
        }
    }
}

private struct StrategyModeBar: View {
    @Binding var mode: StrategyStudioMode

    var body: some View {
        HStack(spacing: 5) {
            ForEach(StrategyStudioMode.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { mode = item }
                } label: {
                    Image(systemName: item.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(mode == item ? CueInColors.textPrimary : CueInColors.textTertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(mode == item ? CueInColors.surfaceSecondary : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityLabel(item.rawValue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(CueInColors.surfacePrimary, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(CueInColors.cardBorder, lineWidth: 0.6))
    }
}

private struct GoalRailChip: View {
    let goal: Goal
    let progress: Double
    let selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: goal.resolvedIconSystemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(goal.color)
            Text(goal.title)
                .font(CueInTypography.captionMedium)
                .foregroundStyle(selected ? CueInColors.textPrimary : CueInColors.textSecondary)
                .lineLimit(1)
            Text("\(Int(progress * 100))")
                .font(CueInTypography.micro)
                .foregroundStyle(CueInColors.textTertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(selected ? CueInColors.surfaceSecondary : CueInColors.surfacePrimary, in: Capsule())
        .overlay(Capsule().strokeBorder(selected ? goal.color.opacity(0.45) : CueInColors.cardBorder, lineWidth: 0.7))
    }
}

private enum StrategyNodeStyle {
    case hero
    case stage
}

private struct StrategyNode: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let style: StrategyNodeStyle

    var body: some View {
        HStack(spacing: CueInSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: style == .hero ? 19 : 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: style == .hero ? 44 : 36, height: style == .hero ? 44 : 36)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(style == .hero ? CueInTypography.headline : CueInTypography.bodyMedium)
                    .foregroundStyle(CueInColors.textPrimary)
                    .lineLimit(2)
                Text(subtitle)
                    .font(CueInTypography.micro)
                    .foregroundStyle(CueInColors.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: style == .hero ? 285 : 235)
        .padding(CueInSpacing.md)
        .background(CueInColors.surfacePrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.16), lineWidth: 0.7))
    }
}

private struct StrategyLaneNode: View {
    let title: String
    let subtitle: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(CueInTypography.micro)
                    .foregroundStyle(tint)
                Spacer()
                Text(value)
                    .font(CueInTypography.micro)
                    .foregroundStyle(CueInColors.textTertiary)
                    .monospacedDigit()
            }
            Text(subtitle)
                .font(CueInTypography.captionMedium)
                .foregroundStyle(CueInColors.textPrimary)
                .lineLimit(3)
                .frame(minHeight: 48, alignment: .topLeading)
        }
        .padding(CueInSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CueInColors.surfacePrimary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(tint.opacity(0.18), lineWidth: 0.7))
    }
}

private struct StrategyToolButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(CueInTypography.micro)
            }
            .foregroundStyle(CueInColors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(CueInColors.surfacePrimary, in: Capsule())
            .overlay(Capsule().strokeBorder(CueInColors.cardBorder, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }
}

private struct StrategyInsightTile: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(CueInTypography.micro)
                    .foregroundStyle(CueInColors.textTertiary)
                Spacer()
            }
            Text(value)
                .font(CueInTypography.captionMedium)
                .foregroundStyle(CueInColors.textPrimary)
                .lineLimit(3)
                .frame(minHeight: 46, alignment: .topLeading)
        }
        .padding(CueInSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CueInColors.surfacePrimary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(CueInColors.cardBorder, lineWidth: 0.6))
    }
}

private struct ReviewSignalStrip: View {
    let goal: Goal
    let staleCount: Int
    let reviewCount: Int

    var body: some View {
        HStack(spacing: CueInSpacing.sm) {
            ReviewSignal(title: "Stalled", value: "\(staleCount)", tint: staleCount == 0 ? CueInColors.success : CueInColors.warning)
            ReviewSignal(title: "Reviews", value: "\(reviewCount)", tint: goal.color)
            ReviewSignal(title: "Stages", value: "\(goal.stages.count)", tint: CueInColors.textSecondary)
        }
    }
}

private struct ReviewSignal: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(CueInTypography.headline)
                .foregroundStyle(CueInColors.textPrimary)
            Text(title)
                .font(CueInTypography.micro)
                .foregroundStyle(CueInColors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CueInSpacing.md)
        .background(CueInColors.surfacePrimary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(tint.opacity(0.18), lineWidth: 0.7))
    }
}

private struct ReviewEntryRow: View {
    let entry: GoalReviewEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(entry.createdAt.formatted(.dateTime.month(.abbreviated).day()))
                .font(CueInTypography.micro)
                .foregroundStyle(CueInColors.textTertiary)
            if !entry.next.isEmpty {
                Text(entry.next)
                    .font(CueInTypography.captionMedium)
                    .foregroundStyle(CueInColors.textPrimary)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                if !entry.moved.isEmpty { miniReviewTag("Moved") }
                if !entry.stalled.isEmpty { miniReviewTag("Stalled") }
                if !entry.changed.isEmpty { miniReviewTag("Changed") }
            }
        }
        .padding(CueInSpacing.md)
        .background(CueInColors.surfacePrimary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(CueInColors.cardBorder, lineWidth: 0.6))
    }

    private func miniReviewTag(_ title: String) -> some View {
        Text(title)
            .font(CueInTypography.micro)
            .foregroundStyle(CueInColors.textTertiary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(CueInColors.activeHint, in: Capsule())
    }
}

private struct StrategySectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(CueInTypography.title)
            .foregroundStyle(CueInColors.textPrimary)
    }
}

private struct StrategyEmptyState: View {
    let icon: String
    let title: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(CueInColors.textSecondary)
                .frame(width: 42, height: 42)
                .background(CueInColors.surfacePrimary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(title)
                .font(CueInTypography.bodyMedium)
                .foregroundStyle(CueInColors.textPrimary)
            Button(action: action) {
                Text(actionTitle)
                    .font(CueInTypography.captionMedium)
                    .foregroundStyle(CueInColors.textPrimary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(CueInColors.surfacePrimary, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CueInSpacing.base)
        .background(CueInColors.activeHint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct EmptyStrategyStudio: View {
    let onCreateGoal: (GoalTemplate?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.lg) {
            StrategyEmptyState(icon: "target", title: "No strategy yet", actionTitle: "Create goal") {
                onCreateGoal(nil)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CueInSpacing.sm) {
                    ForEach(GoalTemplate.library) { template in
                        Button { onCreateGoal(template) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: template.iconName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color(hex: template.colorHex))
                                Text(template.title)
                                    .font(CueInTypography.captionMedium)
                                    .foregroundStyle(CueInColors.textSecondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(CueInColors.surfacePrimary, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.trailing, CueInSpacing.screenHorizontal)
            }
        }
    }
}

private struct StrategyMissingView: View {
    var body: some View {
        VStack(spacing: CueInSpacing.md) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(CueInColors.textTertiary)
            Text("Goal not found")
                .font(CueInTypography.title)
                .foregroundStyle(CueInColors.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CueInColors.background.ignoresSafeArea())
    }
}

#Preview {
    NavigationStack {
        GoalsHomeView(
            store: .shared,
            tasksStore: .shared,
            onCreateGoal: { _ in },
            onPresentSheet: { _ in }
        )
        .navigationDestination(for: GoalStrategyRoute.self) { route in
            switch route {
            case .home:
                GoalsHomeView(store: .shared, tasksStore: .shared, onCreateGoal: { _ in }, onPresentSheet: { _ in })
            case .goal(let id):
                GoalDetailView(goalID: id, store: .shared, tasksStore: .shared, onPresentSheet: { _ in })
            }
        }
    }
    .preferredColorScheme(.dark)
}
