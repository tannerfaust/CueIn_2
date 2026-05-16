import SwiftUI

// MARK: - GoalsHomeView

struct GoalsHomeView: View {
    let store: GoalStrategyStore
    let tasksStore: TasksStore
    let onCreateGoal: (GoalTemplate?) -> Void
    let onPresentSheet: (GoalStrategySheet) -> Void
    /// When `true` (Hub push), show a leading chevron that returns to Hub instead of relying on the system bar alone.
    var showsHubBackButton: Bool = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CueInSpacing.xl) {
                header
                
                if store.activeGoals.isEmpty && store.completedGoals.isEmpty {
                    emptyState
                } else {
                    if !store.activeGoals.isEmpty {
                        goalList(title: "Active", goals: store.activeGoals)
                    }
                    if !store.completedGoals.isEmpty {
                        goalList(title: "Completed", goals: store.completedGoals)
                    }
                }
            }
            .padding(.horizontal, CueInSpacing.screenHorizontal)
            .padding(.top, CueInSpacing.base)
            .padding(.bottom, CueInLayout.scrollBottomInset)
        }
        .background(CueInColors.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(showsHubBackButton)
        .toolbar {
            if showsHubBackButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(CueInColors.textPrimary)
                    }
                    .accessibilityLabel("Back to Hub")
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Goals")
                .font(CueInTypography.largeTitle)
                .foregroundStyle(CueInColors.textPrimary)
            Spacer()
            Button(action: { onCreateGoal(nil) }) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CueInColors.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(CueInColors.surfaceSecondary, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(spacing: CueInSpacing.md) {
            Text("No goals yet.")
                .font(CueInTypography.body)
                .foregroundStyle(CueInColors.textTertiary)
            Button("Create your first goal") {
                onCreateGoal(nil)
            }
            .font(CueInTypography.bodyMedium)
            .foregroundStyle(CueInColors.accentFocus)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 64)
    }

    private func goalList(title: String, goals: [Goal]) -> some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            Text(title.uppercased())
                .font(CueInTypography.micro)
                .foregroundStyle(CueInColors.textTertiary)
                .tracking(1.0)
            
            VStack(spacing: 1) {
                ForEach(goals) { goal in
                    NavigationLink(value: GoalStrategyRoute.goal(goal.id)) {
                        goalRow(goal)
                    }
                    .buttonStyle(.plain)
                    if goal.id != goals.last?.id {
                        Divider().background(CueInColors.divider)
                            .padding(.leading, 12)
                    }
                }
            }
            .background(CueInColors.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous)
                    .strokeBorder(CueInColors.cardBorder, lineWidth: 0.5)
            )
        }
    }

    private func goalRow(_ goal: Goal) -> some View {
        HStack(spacing: CueInSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.title)
                    .font(CueInTypography.bodyMedium)
                    .foregroundStyle(CueInColors.textPrimary)
                if !goal.description.isEmpty {
                    Text(goal.description)
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            let summary = store.progressSummary(goal: goal, tasksStore: tasksStore)
            Text("\(Int(summary.progress * 100))%")
                .font(CueInTypography.caption.monospacedDigit())
                .foregroundStyle(CueInColors.textSecondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CueInColors.textTertiary)
        }
        .padding(16)
    }
}

// MARK: - GoalDetailView

struct GoalDetailView: View {
    let goalID: UUID
    let store: GoalStrategyStore
    let tasksStore: TasksStore
    let onPresentSheet: (GoalStrategySheet) -> Void
    /// When `true` (Hub navigation stack), show a leading chevron that pops this destination.
    var showsHubBackButton: Bool = false

    @State private var viewMode: GoalWorkspaceMode = .list
    @Environment(\.dismiss) private var dismiss

    enum GoalWorkspaceMode: String, CaseIterable, Identifiable {
        case list = "List"
        case roadmap = "Roadmap"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let goal = store.goal(goalID) {
                header(for: goal)
                modePicker
                Divider().background(CueInColors.divider)
                
                Group {
                    if viewMode == .list {
                        StrategyListView(goal: goal, store: store, tasksStore: tasksStore, onPresentSheet: onPresentSheet)
                    } else {
                        StrategyRoadmapView(goal: goal, store: store, tasksStore: tasksStore, onPresentSheet: onPresentSheet)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Goal not found")
                    .foregroundStyle(CueInColors.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(CueInColors.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(showsHubBackButton)
        .toolbar {
            if showsHubBackButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(CueInColors.textPrimary)
                    }
                    .accessibilityLabel("Back")
                }
            }
        }
    }

    private func header(for goal: Goal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(goal.title)
                    .font(CueInTypography.largeTitle)
                    .foregroundStyle(CueInColors.textPrimary)
                Spacer()
                Menu {
                    Button("Edit Goal") { onPresentSheet(.editGoal(goal.id)) }
                    if goal.status != .completed {
                        Button("Mark Completed") { store.setGoalStatus(goal.id, status: .completed) }
                    }
                    Button("Delete Goal", role: .destructive) { 
                        store.deleteGoal(goal.id)
                        dismiss()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CueInColors.textSecondary)
                        .frame(width: 32, height: 32)
                }
            }
            if !goal.description.isEmpty {
                Text(goal.description)
                    .font(CueInTypography.body)
                    .foregroundStyle(CueInColors.textSecondary)
            }
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
        .padding(.top, CueInSpacing.base)
        .padding(.bottom, CueInSpacing.md)
    }

    private var modePicker: some View {
        HStack(spacing: CueInSpacing.md) {
            ForEach(GoalWorkspaceMode.allCases) { mode in
                Button(action: { viewMode = mode }) {
                    Text(mode.rawValue)
                        .font(CueInTypography.captionMedium)
                        .foregroundStyle(viewMode == mode ? CueInColors.textPrimary : CueInColors.textTertiary)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            if viewMode == mode {
                                Rectangle()
                                    .fill(CueInColors.textPrimary)
                                    .frame(height: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
    }
}

// MARK: - StrategyListView (Minimalist Outliner)

struct StrategyListView: View {
    let goal: Goal
    let store: GoalStrategyStore
    let tasksStore: TasksStore
    let onPresentSheet: (GoalStrategySheet) -> Void
    
    @State private var expandedStages: Set<UUID> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(goal.stages) { stage in
                    stageSection(stage)
                }
                
                Button(action: { onPresentSheet(.createStage(goalID: goal.id)) }) {
                    HStack {
                        Image(systemName: "plus")
                        Text("Add Stage")
                    }
                    .font(CueInTypography.bodyMedium)
                    .foregroundStyle(CueInColors.textSecondary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
            }
            .padding(CueInSpacing.screenHorizontal)
            .padding(.bottom, CueInLayout.scrollBottomInset)
        }
        .onAppear {
            if expandedStages.isEmpty {
                if let active = store.currentStage(for: goal) {
                    expandedStages.insert(active.id)
                }
            }
        }
    }
    
    @ViewBuilder
    private func stageSection(_ stage: GoalStage) -> some View {
        let isExpanded = expandedStages.contains(stage.id)
        
        VStack(spacing: 0) {
            // Stage Header
            HStack(spacing: 12) {
                Button(action: { toggle(stage.id) }) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CueInColors.textTertiary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                
                Text(stage.title)
                    .font(CueInTypography.headline)
                    .foregroundStyle(CueInColors.textPrimary)
                
                Spacer()
                
                Menu {
                    Button("Edit Stage") { onPresentSheet(.editStage(goalID: goal.id, stageID: stage.id)) }
                    Button("Add Subgoal") {
                        expandedStages.insert(stage.id)
                        onPresentSheet(.createSubgoal(goalID: goal.id, stageID: stage.id))
                    }
                    Button("Delete Stage", role: .destructive) { store.deleteStage(goalID: goal.id, stageID: stage.id) }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(CueInColors.textTertiary)
                        .padding(4)
                }
            }
            .padding(.vertical, 12)
            .background(CueInColors.background)
            
            // Subgoals
            if isExpanded {
                VStack(spacing: 1) {
                    ForEach(stage.subgoals) { subgoal in
                        subgoalRow(stage: stage, subgoal: subgoal)
                    }
                    Button(action: { onPresentSheet(.createSubgoal(goalID: goal.id, stageID: stage.id)) }) {
                        HStack {
                            Image(systemName: "plus")
                            Text("Add Subgoal")
                        }
                        .font(CueInTypography.body)
                        .foregroundStyle(CueInColors.textTertiary)
                        .padding(.vertical, 10)
                        .padding(.leading, 36) // align with subgoal text
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider().background(CueInColors.divider)
        }
    }
    
    private func subgoalRow(stage: GoalStage, subgoal: GoalSubgoal) -> some View {
        let progress = store.progress(subgoal: subgoal, tasksStore: tasksStore)
        let isDone = progress >= 0.999
        
        return HStack(spacing: 12) {
            Circle()
                .strokeBorder(isDone ? CueInColors.success : CueInColors.textTertiary, lineWidth: 1.5)
                .background(isDone ? CueInColors.success : Color.clear, in: Circle())
                .frame(width: 14, height: 14)
                .overlay {
                    if isDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.black)
                    }
                }
                .onTapGesture {
                    let newStatus: GoalSubgoalStatus = isDone ? .open : .completed
                    store.setSubgoalStatus(goalID: goal.id, stageID: stage.id, subgoalID: subgoal.id, status: newStatus)
                }
            
            Text(subgoal.title)
                .font(CueInTypography.body)
                .foregroundStyle(isDone ? CueInColors.textTertiary : CueInColors.textPrimary)
                .strikethrough(isDone, color: CueInColors.textTertiary)
            
            Spacer()
            
            if !subgoal.linkedWork.isEmpty {
                Image(systemName: "link")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(CueInColors.textTertiary)
            }
            
            Menu {
                Button("Edit Subgoal") { onPresentSheet(.editSubgoal(goalID: goal.id, stageID: stage.id, subgoalID: subgoal.id)) }
                Button("Link Work") { onPresentSheet(.linkWork(goalID: goal.id, stageID: stage.id, subgoalID: subgoal.id)) }
                Button("Delete Subgoal", role: .destructive) { store.deleteSubgoal(goalID: goal.id, stageID: stage.id, subgoalID: subgoal.id) }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(CueInColors.textTertiary)
                    .padding(4)
            }
        }
        .padding(.vertical, 8)
        .padding(.leading, 36)
        .background(CueInColors.background)
    }
    
    private func toggle(_ id: UUID) {
        if expandedStages.contains(id) {
            expandedStages.remove(id)
        } else {
            expandedStages.insert(id)
        }
    }
}

// MARK: - StrategyRoadmapView (Minimalist Sequential Timeline)

struct StrategyRoadmapView: View {
    let goal: Goal
    let store: GoalStrategyStore
    let tasksStore: TasksStore
    let onPresentSheet: (GoalStrategySheet) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 24) {
                ForEach(goal.stages.indices, id: \.self) { index in
                    roadmapColumn(stage: goal.stages[index], index: index)
                }
                
                Button(action: { onPresentSheet(.createStage(goalID: goal.id)) }) {
                    VStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 20))
                        Text("Add Stage")
                            .font(CueInTypography.captionMedium)
                    }
                    .foregroundStyle(CueInColors.textTertiary)
                    .frame(width: 260, height: 100)
                    .background(CueInColors.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(CueInColors.cardBorder, style: StrokeStyle(lineWidth: 1, dash: [4])))
                }
                .buttonStyle(.plain)
            }
            .padding(CueInSpacing.screenHorizontal)
            .padding(.top, CueInSpacing.md)
        }
    }
    
    private func roadmapColumn(stage: GoalStage, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("PHASE \(index + 1)")
                    .font(CueInTypography.micro)
                    .foregroundStyle(CueInColors.textTertiary)
                Text(stage.title)
                    .font(CueInTypography.headline)
                    .foregroundStyle(CueInColors.textPrimary)
            }
            
            // Subgoals
            VStack(spacing: 8) {
                ForEach(stage.subgoals) { subgoal in
                    roadmapSubgoalCard(stage: stage, subgoal: subgoal)
                }
                
                Button(action: { onPresentSheet(.createSubgoal(goalID: goal.id, stageID: stage.id)) }) {
                    HStack {
                        Image(systemName: "plus")
                        Text("Add Subgoal")
                    }
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(CueInColors.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 260)
    }
    
    private func roadmapSubgoalCard(stage: GoalStage, subgoal: GoalSubgoal) -> some View {
        let progress = store.progress(subgoal: subgoal, tasksStore: tasksStore)
        let isDone = progress >= 0.999
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(subgoal.title)
                    .font(CueInTypography.body)
                    .foregroundStyle(isDone ? CueInColors.textTertiary : CueInColors.textPrimary)
                    .strikethrough(isDone, color: CueInColors.textTertiary)
                    .lineLimit(2)
                Spacer()
            }
            
            if !subgoal.linkedWork.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                    Text("\(subgoal.linkedWork.count) Linked")
                }
                .font(CueInTypography.micro)
                .foregroundStyle(CueInColors.textTertiary)
            }
            
            // Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(CueInColors.surfaceTertiary)
                    Capsule().fill(isDone ? CueInColors.success : CueInColors.textSecondary)
                        .frame(width: max(0, geo.size.width * progress))
                }
            }
            .frame(height: 3)
        }
        .padding(12)
        .background(CueInColors.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(CueInColors.cardBorder, lineWidth: 0.5)
        )
        .onTapGesture {
            onPresentSheet(.editSubgoal(goalID: goal.id, stageID: stage.id, subgoalID: subgoal.id))
        }
    }
}
