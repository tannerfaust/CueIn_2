import SwiftUI

// MARK: - QuickCaptureSheet
/// Super-fast task entry. Autofocused title, inline chips below for
/// field / project / execution / priority / due-date. Save lands the task
/// directly into `TasksStore`; a "More…" shortcut opens the full editor
/// for the caller to handle if it wants to chain (not wired here).

struct QuickCaptureSheet: View {

    var store: TasksStore
    var onDismiss: () -> Void
    var onExpand: (TaskItem) -> Void
    /// Fired after **Add task** commits the new row to ``TasksStore`` (before dismiss).
    var onSaved: ((TaskItem) -> Void)?
    /// When `false`, hides the sheet drag handle (e.g. when embedded in another nav stack).
    var showsDragHandle: Bool

    @MainActor init(
        store: TasksStore,
        captureDefaultsToToday: Bool = true,
        onSaved: ((TaskItem) -> Void)? = nil,
        onDismiss: @escaping () -> Void,
        onExpand: @escaping (TaskItem) -> Void = { _ in },
        showsDragHandle: Bool = true
    ) {
        self.store = store
        self.onSaved = onSaved
        self.onDismiss = onDismiss
        self.onExpand = onExpand
        self.showsDragHandle = showsDragHandle
        _dueOption = State(initialValue: captureDefaultsToToday ? .today : .noDate)
    }

    /// Uses ``TasksStore/shared`` — separated so Swift 6 does not infer a nonisolated default-arg access to the actor-isolated singleton.
    @MainActor init(
        captureDefaultsToToday: Bool = true,
        onSaved: ((TaskItem) -> Void)? = nil,
        onDismiss: @escaping () -> Void,
        onExpand: @escaping (TaskItem) -> Void = { _ in },
        showsDragHandle: Bool = true
    ) {
        self.init(
            store: TasksStore.shared,
            captureDefaultsToToday: captureDefaultsToToday,
            onSaved: onSaved,
            onDismiss: onDismiss,
            onExpand: onExpand,
            showsDragHandle: showsDragHandle
        )
    }

    @State private var title: String = ""
    @State private var fieldID: UUID? = nil
    @State private var projectID: UUID? = nil
    @State private var executionType: TaskExecutionType? = nil
    @State private var priority: TaskPriority = .normal
    @State private var dueOption: DueOption
    @State private var saveHaptic = false
    @State private var selectHaptic = false

    @FocusState private var titleFocused: Bool

    enum DueOption: Hashable {
        case today, tomorrow, noDate
        var label: String {
            switch self {
            case .today:    return "Today"
            case .tomorrow: return "Tomorrow"
            case .noDate:   return "Inbox"
            }
        }
        var icon: String {
            switch self {
            case .today:    return "sun.max.fill"
            case .tomorrow: return "arrow.turn.up.right"
            case .noDate:   return "tray.fill"
            }
        }
        var date: Date? {
            switch self {
            case .today:    return Calendar.current.startOfDay(for: Date())
            case .tomorrow: return Calendar.current.date(byAdding: .day, value: 1,
                                                         to: Calendar.current.startOfDay(for: Date()))
            case .noDate:   return nil
            }
        }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            if showsDragHandle {
                handle
            }
            titleField
                .padding(.horizontal, CueInSpacing.base)
                .padding(.top, CueInSpacing.md)

            chips
                .padding(.top, CueInSpacing.md)

            Spacer(minLength: CueInSpacing.md)

            saveRow
                .padding(.horizontal, CueInSpacing.base)
                .padding(.bottom, CueInSpacing.md)
        }
        .background(CueInColors.surfacePrimary)
        .sensoryFeedback(.success, trigger: saveHaptic)
        .sensoryFeedback(.selection, trigger: selectHaptic)
        .onAppear {
            // Default to first field if none chosen
            if fieldID == nil { fieldID = store.fields.first?.id }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                titleFocused = true
            }
        }
    }

    // MARK: Handle + title

    private var handle: some View {
        Capsule()
            .fill(CueInColors.textTertiary.opacity(0.4))
            .frame(width: 36, height: 4)
            .padding(.top, CueInSpacing.sm)
    }

    private var titleField: some View {
        HStack(spacing: CueInSpacing.md) {
            ZStack {
                Circle()
                    .strokeBorder(CueInColors.textTertiary.opacity(0.6), lineWidth: 1.5)
                    .frame(width: 22, height: 22)
            }

            TextField("What needs doing?", text: $title, axis: .vertical)
                .font(CueInTypography.title)
                .foregroundStyle(CueInColors.textPrimary)
                .tint(CueInColors.accentFocus)
                .focused($titleFocused)
                .submitLabel(.done)
                .onSubmit { save() }
                .lineLimit(1...3)
        }
    }

    // MARK: Chips row

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CueInSpacing.sm) {
                // Field
                Menu {
                    ForEach(store.fields) { f in
                        Button {
                            if fieldID != f.id { projectID = nil }
                            fieldID = f.id
                            selectHaptic.toggle()
                        } label: { Label(f.name, systemImage: f.resolvedIconSystemName) }
                    }
                } label: {
                    chipLabel(
                        icon: store.field(fieldID)?.resolvedIconSystemName ?? "square.grid.2x2",
                        text: store.field(fieldID)?.name ?? "Field",
                        accent: store.field(fieldID)?.color
                    )
                }
                .menuStyle(.borderlessButton)
                .cueInMenuInteractionStability()

                // Project
                let projectOptions = fieldID.map(store.projects) ?? store.projects
                Menu {
                    Button { projectID = nil; selectHaptic.toggle() } label: {
                        Label("No project", systemImage: "xmark")
                    }
                    ForEach(projectOptions) { p in
                        Button {
                            projectID = p.id
                            if fieldID == nil { fieldID = p.fieldID }
                            selectHaptic.toggle()
                        } label: { Label(p.name, systemImage: p.resolvedIconSystemName) }
                    }
                } label: {
                    chipLabel(
                        icon: store.project(projectID)?.resolvedIconSystemName ?? "folder",
                        text: store.project(projectID)?.name ?? "Project",
                        accent: store.project(projectID).map { store.color(for: $0) }
                    )
                }
                .menuStyle(.borderlessButton)
                .cueInMenuInteractionStability()

                // Execution type — inline segmented
                executionSegmented

                // Priority
                Menu {
                    ForEach(TaskPriority.allCases) { p in
                        Button { priority = p; selectHaptic.toggle() } label: {
                            Label(p.label, systemImage: p.icon)
                        }
                    }
                } label: {
                    chipLabel(
                        icon: priority.icon,
                        text: priority.label,
                        accent: priority.color
                    )
                }
                .menuStyle(.borderlessButton)
                .cueInMenuInteractionStability()

                // Due
                Menu {
                    Button { dueOption = .today; selectHaptic.toggle() }    label: { Label("Today",    systemImage: "sun.max") }
                    Button { dueOption = .tomorrow; selectHaptic.toggle() } label: { Label("Tomorrow", systemImage: "arrow.turn.up.right") }
                    Button { dueOption = .noDate; selectHaptic.toggle() }   label: { Label("Inbox",    systemImage: "tray") }
                } label: {
                    chipLabel(
                        icon: dueOption.icon,
                        text: dueOption.label,
                        accent: dueOption == .today ? CueInColors.accentFixed : nil
                    )
                }
                .menuStyle(.borderlessButton)
                .cueInMenuInteractionStability()
            }
            .padding(.horizontal, CueInSpacing.base)
        }
    }

    private var executionSegmented: some View {
        HStack(spacing: 0) {
            Button {
                executionType = nil
                selectHaptic.toggle()
            } label: {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(executionType == nil ? CueInColors.textPrimary : CueInColors.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(executionType == nil ? CueInColors.surfacePrimary.opacity(0.7) : Color.clear)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            ForEach(TaskExecutionType.allCases) { type in
                let on = executionType == type
                Button {
                    executionType = type
                    selectHaptic.toggle()
                } label: {
                    Image(systemName: type.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(on ? CueInColors.textPrimary : CueInColors.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(on ? CueInColors.surfacePrimary.opacity(0.7) : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .background(CueInColors.surfaceSecondary)
        .clipShape(Capsule())
        .overlay(
            Capsule().strokeBorder(CueInColors.divider, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func chipLabel(icon: String, text: String, accent: Color?) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accent ?? CueInColors.textSecondary)
            Text(text)
                .font(CueInTypography.captionMedium)
                .foregroundStyle(accent == nil ? CueInColors.textSecondary : CueInColors.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, CueInSpacing.md)
        .padding(.vertical, 8)
        .background(
            accent.map { $0.opacity(0.12) } ?? CueInColors.surfaceSecondary
        )
        .clipShape(Capsule())
        .overlay(
            Capsule().strokeBorder(
                accent?.opacity(0.3) ?? CueInColors.divider,
                lineWidth: 0.5
            )
        )
    }

    // MARK: Save

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var saveRow: some View {
        HStack(spacing: CueInSpacing.sm) {
            Button {
                if let t = buildDraft() { onExpand(t) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3")
                    Text("More…")
                }
                .font(CueInTypography.captionMedium)
                .foregroundStyle(CueInColors.textSecondary)
                .padding(.horizontal, CueInSpacing.md)
                .padding(.vertical, 12)
                .background(CueInColors.surfaceSecondary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.4)

            Button(action: save) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Add task")
                        .font(CueInTypography.bodyMedium)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    canSave ? CueInColors.accentFocus : CueInColors.surfaceTertiary
                )
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
    }

    private func buildDraft() -> TaskItem? {
        guard canSave else { return nil }
        return TaskItem(
            title: title.trimmingCharacters(in: .whitespaces),
            fieldID: fieldID,
            projectID: projectID,
            executionType: executionType,
            priority: priority,
            scheduledDate: dueOption.date,
            status: dueOption.date == nil ? .inbox : .scheduled
        )
    }

    private func save() {
        guard let draft = buildDraft() else { return }
        store.addTask(draft)
        onSaved?(draft)
        saveHaptic.toggle()
        onDismiss()
    }
}
