import SwiftUI

// MARK: - ReorderableTaskList
/// Task stacks for the Tasks tab — flat Linear-style rows: no grouped “card” chrome,
/// hairline separators, and section headers as quiet labels.

struct ReorderableTaskList: View {

    @Bindable private var store = TasksStore.shared
    @Bindable private var dayPlanner = TodayViewModel.shared

    let tasks: [TaskItem]
    let listKey: String
    var onOpenTask: (UUID) -> Void

    var sectionTitle: String? = nil
    var sectionSubtitle: String? = nil
    var sectionIcon: String? = nil
    var sectionTint: Color? = nil
    var onPoolMove: (TaskItem, Bool) -> Void = { _, _ in }
    var onDeleteTask: (TaskItem, String) -> Void = { task, _ in
        TasksStore.shared.deleteTask(task.id)
    }

    var body: some View {
        let ordered = store.orderedTasks(tasks, listKey: listKey)

        VStack(alignment: .leading, spacing: 0) {
            if let title = sectionTitle {
                sectionHeader(title: title)
                    .padding(.bottom, CueInSpacing.sm)
            }

            LazyVStack(spacing: 0) {
                ForEach(Array(ordered.enumerated()), id: \.element.id) { index, t in
                    TaskItemRow(
                        task: t,
                        store: store,
                        onToggle: { store.toggleComplete(t.id) },
                        onOpen: { onOpenTask(t.id) },
                        onDelete: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                onDeleteTask(t, listKey)
                            }
                        },
                        onSchedule: { store.scheduleTask(t.id, on: $0) },
                        compactStyle: true,
                        isQueuedForToday: dayPlanner.isPlannerTaskQueuedForToday(t.id),
                        onQueueToday: {
                            let wasQueued = dayPlanner.isPlannerTaskQueuedForToday(t.id)
                            let moved = store.tasks.first(where: { $0.id == t.id }) ?? t
                            onPoolMove(moved, !wasQueued)
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                                if wasQueued {
                                    dayPlanner.dequeuePlannerTask(t.id)
                                } else {
                                    guard let fresh = store.tasks.first(where: { $0.id == t.id }) else { return }
                                    dayPlanner.enqueuePlannerTask(fresh)
                                }
                            }
                        }
                    )
                    .transition(poolTransition(isQueued: dayPlanner.isPlannerTaskQueuedForToday(t.id)))

                    if index < ordered.count - 1 {
                        Rectangle()
                            .fill(CueInColors.divider.opacity(0.45))
                            .frame(height: 1)
                            .padding(.leading, 32)
                    }
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.82), value: ordered.map(\.id))
        }
    }

    private func poolTransition(isQueued: Bool) -> AnyTransition {
        let edge: Edge = isQueued ? .leading : .trailing
        return .asymmetric(
            insertion: .scale(scale: 0.96, anchor: .center)
                .combined(with: .opacity)
                .combined(with: .move(edge: edge)),
            removal: .scale(scale: 0.96, anchor: .center)
                .combined(with: .opacity)
                .combined(with: .move(edge: edge))
        )
    }

    // MARK: Section header

    @ViewBuilder
    private func sectionHeader(title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let icon = sectionIcon, let tint = sectionTint {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tint.opacity(0.9))
            }
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CueInColors.textTertiary)
            Spacer(minLength: 8)
            if let sub = sectionSubtitle, !sub.isEmpty {
                Text(sub)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(CueInColors.textTertiary.opacity(0.85))
                    .monospacedDigit()
            }
        }
        .textCase(nil)
    }
}
