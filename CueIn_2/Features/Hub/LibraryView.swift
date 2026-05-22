import SwiftUI

// MARK: - Library (Hub)

enum LibraryHomeSegment: String, CaseIterable, Identifiable {
    case tasks
    case timeMaps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tasks: return "Tasks"
        case .timeMaps: return "TimeMaps"
        }
    }
}

// MARK: - TimeMaps library navigation (pages inside the sheet)

private enum LibraryTimeMapNav: Hashable {
    /// All day layouts: yours + bundled, single list.
    case timeMapsList
    /// Saved blocks + entry to browse blocks grouped by parent TimeMap.
    case timeBlocksHub
    /// Blocks taken from one bundled / included TimeMap.
    case timeMapBlocksDetail(UUID)
    /// New saved TimeMap (preview editor, no Start).
    case timeMapEditorNew
    /// Edit an existing TimeMap layout in the library editor.
    case timeMapEditorExisting(UUID)
}

// MARK: - Sample block from a bundled day (not a whole saved schedule)

private struct SampleBlockItem: Identifiable {
    let formulaID: UUID
    let formulaName: String
    let block: DayFormulaBlockTemplate

    var id: String { "\(formulaID.uuidString)-\(block.id.uuidString)" }
}

// MARK: - Full Library sheet

struct LibraryView: View {
    @Environment(\.dismiss) private var dismiss

    let initialSegment: LibraryHomeSegment
    let onRequestDismiss: () -> Void

    @Bindable private var tasksStore = TasksStore.shared
    @State private var segment: LibraryHomeSegment
    @State private var schedulePendingDelete: DayFormulaTemplate?
    @State private var blockPendingDelete: DayFormulaBlockTemplate?
    @State private var taskEditID: UUID?
    @State private var libraryEpoch = 0
    @State private var timeMapLibraryPath = NavigationPath()
    @AppStorage(CueInAppDataKeys.gimmickDemoRemoved) private var gimmickDemoRemoved = false
    @AppStorage(CueInAppDataKeys.hideBundledDummyTestDayTimeMap) private var hideBundledDummyTestDayTimeMap = false

    init(initialSegment: LibraryHomeSegment = .tasks, onRequestDismiss: @escaping () -> Void) {
        self.initialSegment = initialSegment
        self.onRequestDismiss = onRequestDismiss
        _segment = State(initialValue: initialSegment)
    }

    private var savedTasks: [TaskItem] {
        tasksStore.tasks
            .filter(\.savesToArchive)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        NavigationStack(path: $timeMapLibraryPath) {
            VStack(spacing: 0) {
                Picker("Section", selection: $segment) {
                    ForEach(LibraryHomeSegment.allCases) { seg in
                        Text(seg.title).tag(seg)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, CueInSpacing.screenHorizontal)
                .padding(.vertical, CueInSpacing.sm)

                Group {
                    switch segment {
                    case .tasks:
                        ScrollView {
                            tasksSection
                        }
                        .scrollIndicators(.hidden)
                    case .timeMaps:
                        ScrollView {
                            timeMapsLibraryHubRoot
                        }
                        .scrollIndicators(.hidden)
                    }
                }
            }
            .background(CueInColors.background.ignoresSafeArea())
            .navigationTitle("Library")
            .cueInNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: CueInToolbarPlacement.topBarTrailing) {
                    Button("Done") {
                        onRequestDismiss()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(CueInColors.textPrimary)
                }
            }
            .navigationDestination(for: LibraryTimeMapNav.self) { route in
                switch route {
                case .timeMapsList:
                    LibraryTimeMapsListPage(
                        libraryEpoch: $libraryEpoch,
                        onOpenTimeMapEditor: { id in
                            timeMapLibraryPath.append(LibraryTimeMapNav.timeMapEditorExisting(id))
                        },
                        onUseTimeMap: { id in
                            Self.applySavedSchedule(id: id)
                            onRequestDismiss()
                            dismiss()
                        },
                        onDeleteRequest: { schedulePendingDelete = $0 }
                    )
                case .timeBlocksHub:
                    LibraryTimeBlocksHubPage(
                        libraryEpoch: $libraryEpoch,
                        onInsertBlock: { useBlockTemplate($0) },
                        onDeleteBlockRequest: { blockPendingDelete = $0 }
                    )
                case .timeMapBlocksDetail(let formulaID):
                    LibraryTimeMapBlocksDetailPage(
                        formulaID: formulaID,
                        libraryEpoch: libraryEpoch,
                        onInsertBlock: { useBlockTemplate($0) }
                    )
                case .timeMapEditorNew:
                    LibraryTimeMapEditorView(
                        editingFormulaID: nil,
                        libraryEpoch: $libraryEpoch,
                        onDismissLibrary: {
                            onRequestDismiss()
                            dismiss()
                        }
                    )
                case .timeMapEditorExisting(let id):
                    LibraryTimeMapEditorView(
                        editingFormulaID: id,
                        libraryEpoch: $libraryEpoch,
                        onDismissLibrary: {
                            onRequestDismiss()
                            dismiss()
                        }
                    )
                }
            }
        }
        .onAppear { segment = initialSegment }
        .onChange(of: segment) { _, new in
            if new != .timeMaps {
                timeMapLibraryPath = NavigationPath()
            }
        }
        .sheet(item: Binding(
            get: { taskEditID.map { IdentifiableUUID(id: $0) } },
            set: { taskEditID = $0?.id }
        )) { wrapped in
            TaskDetailSheet(mode: .edit(wrapped.id), store: tasksStore, onDismiss: { taskEditID = nil })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .alert("Remove this TimeMap from your library?", isPresented: Binding(
            get: { schedulePendingDelete != nil },
            set: { if !$0 { schedulePendingDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { schedulePendingDelete = nil }
            Button("Delete", role: .destructive) {
                if let s = schedulePendingDelete {
                    FormulaLibraryService.removeCustomSchedule(id: s.id)
                    libraryEpoch += 1
                }
                schedulePendingDelete = nil
            }
        } message: {
            Text(schedulePendingDelete?.name ?? "")
        }
        .alert("Delete this TimeMap block preset?", isPresented: Binding(
            get: { blockPendingDelete != nil },
            set: { if !$0 { blockPendingDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { blockPendingDelete = nil }
            Button("Delete", role: .destructive) {
                if let b = blockPendingDelete {
                    FormulaLibraryService.removeCustomBlockPreset(id: b.id)
                    libraryEpoch += 1
                }
                blockPendingDelete = nil
            }
        } message: {
            Text(blockPendingDelete?.title ?? "")
        }
    }

    // MARK: TimeMaps hub (two pages)

    private var timeMapsLibraryHubRoot: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            Text("Browse day layouts and reusable blocks on their own screens.")
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: CueInSpacing.sm) {
                NavigationLink(value: LibraryTimeMapNav.timeMapsList) {
                    libraryHubRow(
                        icon: "rectangle.split.3x1",
                        title: "TimeMaps",
                        subtitle: timeMapsHubSubtitle
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(value: LibraryTimeMapNav.timeBlocksHub) {
                    libraryHubRow(
                        icon: "square.split.2x1",
                        title: "Time blocks",
                        subtitle: timeBlocksHubSubtitle
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
        .padding(.top, CueInSpacing.md)
        .padding(.bottom, CueInLayout.scrollBottomInset)
    }

    private var timeMapsHubSubtitle: String {
        _ = libraryEpoch
        _ = gimmickDemoRemoved
        _ = hideBundledDummyTestDayTimeMap
        let n = FormulaLibraryService.customSchedules().count + FormulaLibraryService.bundledLibraryTemplates.count
        return n == 0 ? "No layouts yet" : "\(n) layout\(n == 1 ? "" : "s")"
    }

    private var timeBlocksHubSubtitle: String {
        _ = libraryEpoch
        _ = gimmickDemoRemoved
        _ = hideBundledDummyTestDayTimeMap
        let saved = FormulaLibraryService.customBlockPresets().count
        let fromMaps = FormulaLibraryService.bundledLibraryTemplates.reduce(0) { $0 + $1.blocks.count }
        if saved == 0, fromMaps == 0 { return "Nothing to show" }
        if saved == 0 { return "\(fromMaps) from included TimeMaps" }
        if fromMaps == 0 { return "\(saved) saved" }
        return "\(saved) saved · \(fromMaps) from TimeMaps"
    }

    private func libraryHubRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: CueInSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(CueInColors.textPrimary)
                .frame(width: 44, height: 44)
                .background(CueInColors.surfaceSecondary.opacity(0.88), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(CueInTypography.bodyMedium)
                    .foregroundStyle(CueInColors.textPrimary)
                Text(subtitle)
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CueInColors.textTertiary)
        }
        .padding(CueInSpacing.base)
        .background(CueInColors.surfacePrimary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(CueInColors.cardBorder, lineWidth: 0.5)
        )
    }

    // MARK: Tasks

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.lg) {
            sectionChromeTitle("Bookmarked", subtitle: "Tasks you marked to keep close.")

            if savedTasks.isEmpty {
                emptyStatePanel(
                    icon: "bookmark.circle",
                    title: "Nothing bookmarked yet",
                    message: "In any task, enable “Save to archive” to pin it here."
                )
            } else {
                LazyVStack(spacing: CueInSpacing.md) {
                    ForEach(savedTasks) { task in
                        bookmarkedTaskCard(task)
                    }
                }
            }
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
        .padding(.top, CueInSpacing.md)
        .padding(.bottom, CueInLayout.scrollBottomInset)
    }

    private func bookmarkedTaskCard(_ task: TaskItem) -> some View {
        Button {
            taskEditID = task.id
        } label: {
            HStack(alignment: .center, spacing: CueInSpacing.md) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(CueInColors.accentFocus)
                    .frame(width: 4)
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: CueInSpacing.sm) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(CueInColors.accentFocus)
                        Text(task.title)
                            .font(CueInTypography.bodyMedium)
                            .foregroundStyle(CueInColors.textPrimary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                    }
                    if let projectName = task.projectID.flatMap({ tasksStore.project($0)?.name }) {
                        Text(projectName.uppercased())
                            .font(CueInTypography.micro)
                            .foregroundStyle(CueInColors.textTertiary)
                            .tracking(0.6)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CueInColors.textTertiary)
            }
            .padding(CueInSpacing.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(CueInColors.surfacePrimary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                CueInColors.cardBorder.opacity(0.9),
                                CueInColors.cardBorder.opacity(0.35),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.6
                    )
            )
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                removeBookmark(from: task)
            } label: {
                Label("Remove bookmark", systemImage: "bookmark.slash")
            }
        }
    }

    private func removeBookmark(from task: TaskItem) {
        var next = task
        next.savesToArchive = false
        tasksStore.updateTask(next)
    }

    // MARK: Actions

    private func useBlockTemplate(_ template: DayFormulaBlockTemplate) {
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .cueInSwitchTab,
                object: nil,
                userInfo: [CueInShellNotification.switchTabUserInfoKey: AppTab.schedule.rawValue]
            )
            try? await Task.sleep(for: .milliseconds(280))
            TodayViewModel.shared.setDayEngineMode(.formulaBased)
            TodayViewModel.shared.reloadAvailableFormulasFromLibrary()
            _ = TodayViewModel.shared.insertFormulaBlock(from: template)
            onRequestDismiss()
            dismiss()
        }
    }

    // MARK: Chrome

    private func sectionChromeTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(CueInTypography.micro)
                .foregroundStyle(CueInColors.textTertiary)
                .tracking(1.1)
            Text(subtitle)
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func emptyStatePanel(icon: String, title: String, message: String) -> some View {
        VStack(spacing: CueInSpacing.md) {
            ZStack {
                Circle()
                    .fill(CueInColors.surfaceSecondary.opacity(0.65))
                    .frame(width: 72, height: 72)
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(CueInColors.textTertiary)
            }
            Text(title)
                .font(CueInTypography.bodyMedium)
                .foregroundStyle(CueInColors.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, CueInSpacing.xl)
        .padding(.horizontal, CueInSpacing.lg)
        .glassSurface(cornerRadius: 22)
    }

    static func applySavedSchedule(id: UUID) {
        NotificationCenter.default.post(
            name: .cueInSwitchTab,
            object: nil,
            userInfo: [CueInShellNotification.switchTabUserInfoKey: AppTab.schedule.rawValue]
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            NotificationCenter.default.post(
                name: .cueInApplySavedFormula,
                object: nil,
                userInfo: [CueInShellNotification.formulaIDUserInfoKey: id.uuidString]
            )
        }
    }
}

// MARK: - TimeMaps list page (unified: yours + included)

private struct IdentifiedTimeMapRow: Identifiable {
    var id: String { "\(isYours ? "y" : "n")-\(formula.id.uuidString)" }
    let formula: DayFormulaTemplate
    let isYours: Bool
}

private struct LibraryTimeMapsListPage: View {
    @Binding var libraryEpoch: Int
    let onOpenTimeMapEditor: (UUID) -> Void
    let onUseTimeMap: (UUID) -> Void
    let onDeleteRequest: (DayFormulaTemplate) -> Void

    @AppStorage(CueInAppDataKeys.gimmickDemoRemoved) private var gimmickDemoRemoved = false
    @AppStorage(CueInAppDataKeys.hideBundledDummyTestDayTimeMap) private var hideBundledDummyTestDayTimeMap = false
    @State private var query = ""
    @State private var formulaConfirmApplyToRunPage: DayFormulaTemplate?

    private var queryTrimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var userLayouts: [DayFormulaTemplate] {
        _ = libraryEpoch
        _ = gimmickDemoRemoved
        _ = hideBundledDummyTestDayTimeMap
        let base = FormulaLibraryService.customSchedules()
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return filterSchedules(base)
    }

    private var includedLayouts: [DayFormulaTemplate] {
        _ = libraryEpoch
        _ = gimmickDemoRemoved
        _ = hideBundledDummyTestDayTimeMap
        let base = FormulaLibraryService.bundledLibraryTemplates
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return filterSchedules(base)
    }

    private var combinedLayoutRows: [IdentifiedTimeMapRow] {
        userLayouts.map { IdentifiedTimeMapRow(formula: $0, isYours: true) }
            + includedLayouts.map { IdentifiedTimeMapRow(formula: $0, isYours: false) }
    }

    private func filterSchedules(_ list: [DayFormulaTemplate]) -> [DayFormulaTemplate] {
        let q = queryTrimmed.lowercased()
        guard !q.isEmpty else { return list }
        return list.filter {
            $0.name.lowercased().contains(q)
                || $0.summary.lowercased().contains(q)
                || $0.previewTitles.lowercased().contains(q)
        }
    }

    var body: some View {
        List {
            if combinedLayoutRows.isEmpty {
                ContentUnavailableView(
                    "No TimeMaps",
                    systemImage: "rectangle.split.3x1",
                    description: Text(queryTrimmed.isEmpty ? "Save a day from TimeMap or use included layouts." : "Nothing matches your search.")
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(combinedLayoutRows) { row in
                        timeMapListRow(row)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if row.isYours {
                                    Button(role: .destructive) {
                                        onDeleteRequest(row.formula)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(CueInColors.background)
        .navigationTitle("TimeMaps")
        .cueInNavigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search TimeMaps")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: LibraryTimeMapNav.timeMapEditorNew) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(CueInColors.textPrimary)
                }
            }
        }
        .alert(
            "Put on run page?",
            isPresented: Binding(
                get: { formulaConfirmApplyToRunPage != nil },
                set: { if !$0 { formulaConfirmApplyToRunPage = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                formulaConfirmApplyToRunPage = nil
            }
            Button("Put on run page") {
                if let f = formulaConfirmApplyToRunPage {
                    onUseTimeMap(f.id)
                }
                formulaConfirmApplyToRunPage = nil
            }
        } message: {
            if let f = formulaConfirmApplyToRunPage {
                Text("Put «\(f.name)» on the run page?")
            }
        }
    }

    private func timeMapListRow(_ row: IdentifiedTimeMapRow) -> some View {
        let formula = row.formula
        let isYours = row.isYours
        return HStack(spacing: CueInSpacing.md) {
            Button {
                onOpenTimeMapEditor(formula.id)
            } label: {
                HStack(spacing: CueInSpacing.md) {
                    Image(systemName: formula.symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CueInColors.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(CueInColors.surfaceSecondary.opacity(0.88), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(formula.name)
                            .font(CueInTypography.bodyMedium)
                            .foregroundStyle(CueInColors.textPrimary)
                            .lineLimit(2)
                        Text("\(formula.blockCount) blocks · \(formula.targetDurationLabel) · \(isYours ? "Yours" : "Included")")
                            .font(CueInTypography.micro)
                            .foregroundStyle(CueInColors.textTertiary)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                formulaConfirmApplyToRunPage = formula
            } label: {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(CueInColors.accentFocus)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Put on TimeMap run page")
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Time blocks hub (saved + drill into each TimeMap)

private struct LibraryTimeBlocksHubPage: View {
    @Binding var libraryEpoch: Int
    let onInsertBlock: (DayFormulaBlockTemplate) -> Void
    let onDeleteBlockRequest: (DayFormulaBlockTemplate) -> Void

    @AppStorage(CueInAppDataKeys.gimmickDemoRemoved) private var gimmickDemoRemoved = false
    @AppStorage(CueInAppDataKeys.hideBundledDummyTestDayTimeMap) private var hideBundledDummyTestDayTimeMap = false
    @State private var query = ""

    private var queryTrimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var savedBlocks: [DayFormulaBlockTemplate] {
        _ = libraryEpoch
        _ = gimmickDemoRemoved
        _ = hideBundledDummyTestDayTimeMap
        let base = FormulaLibraryService.customBlockPresets()
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return filterUserBlocks(base)
    }

    private var parentMaps: [DayFormulaTemplate] {
        _ = libraryEpoch
        _ = gimmickDemoRemoved
        _ = hideBundledDummyTestDayTimeMap
        return FormulaLibraryService.bundledLibraryTemplates
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var filteredParentMaps: [DayFormulaTemplate] {
        let q = queryTrimmed.lowercased()
        guard !q.isEmpty else { return parentMaps }
        return parentMaps.filter {
            $0.name.lowercased().contains(q)
                || $0.blocks.contains(where: { b in
                    b.title.lowercased().contains(q) || b.type.label.lowercased().contains(q)
                })
        }
    }

    private func filterUserBlocks(_ list: [DayFormulaBlockTemplate]) -> [DayFormulaBlockTemplate] {
        let q = queryTrimmed.lowercased()
        guard !q.isEmpty else { return list }
        return list.filter { $0.title.lowercased().contains(q) || $0.type.label.lowercased().contains(q) }
    }

    var body: some View {
        List {
            Section {
                if savedBlocks.isEmpty {
                    Text("No saved block presets")
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textTertiary)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(savedBlocks) { block in
                        blockPresetRow(block: block, canDelete: true)
                    }
                }
            } header: {
                Text("Saved")
                    .font(CueInTypography.micro)
                    .foregroundStyle(CueInColors.textTertiary)
                    .textCase(.uppercase)
            }

            Section {
                if filteredParentMaps.isEmpty {
                    Text(parentMaps.isEmpty ? "No included TimeMaps" : "No matches")
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textTertiary)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(filteredParentMaps) { formula in
                        NavigationLink(value: LibraryTimeMapNav.timeMapBlocksDetail(formula.id)) {
                            HStack(spacing: CueInSpacing.md) {
                                Image(systemName: formula.symbol)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(CueInColors.textPrimary)
                                    .frame(width: 36, height: 36)
                                    .background(CueInColors.surfaceSecondary.opacity(0.88), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(formula.name)
                                        .font(CueInTypography.bodyMedium)
                                        .foregroundStyle(CueInColors.textPrimary)
                                        .lineLimit(2)
                                    Text("\(formula.blocks.count) blocks")
                                        .font(CueInTypography.micro)
                                        .foregroundStyle(CueInColors.textTertiary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            } header: {
                Text("From TimeMaps")
                    .font(CueInTypography.micro)
                    .foregroundStyle(CueInColors.textTertiary)
                    .textCase(.uppercase)
            } footer: {
                Text("Open a TimeMap to browse its blocks without loading one long list.")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textTertiary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(CueInColors.background)
        .navigationTitle("Time blocks")
        .cueInNavigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search blocks & TimeMaps")
    }

    private func blockPresetRow(block: DayFormulaBlockTemplate, canDelete: Bool) -> some View {
        HStack(spacing: CueInSpacing.md) {
            Image(systemName: block.timelineGlyph ?? block.type.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CueInColors.textSecondary)
                .frame(width: 32, height: 32)
                .background(CueInColors.surfaceSecondary.opacity(0.75), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(block.title)
                    .font(CueInTypography.bodyMedium)
                    .foregroundStyle(CueInColors.textPrimary)
                    .lineLimit(2)
                Text(ScheduleBlockFormat.durationLabel(minutes: block.durationMinutes))
                    .font(CueInTypography.micro)
                    .foregroundStyle(CueInColors.textTertiary)
            }

            Spacer(minLength: 0)

            Button {
                onInsertBlock(block)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(CueInColors.accentFocus)
            }
            .buttonStyle(.borderless)

            if canDelete {
                Button {
                    onDeleteBlockRequest(block)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(CueInColors.textTertiary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Blocks from one TimeMap

private struct LibraryTimeMapBlocksDetailPage: View {
    let formulaID: UUID
    let libraryEpoch: Int
    let onInsertBlock: (DayFormulaBlockTemplate) -> Void

    @AppStorage(CueInAppDataKeys.gimmickDemoRemoved) private var gimmickDemoRemoved = false
    @AppStorage(CueInAppDataKeys.hideBundledDummyTestDayTimeMap) private var hideBundledDummyTestDayTimeMap = false
    @State private var query = ""

    private var queryTrimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var formula: DayFormulaTemplate? {
        _ = libraryEpoch
        _ = gimmickDemoRemoved
        _ = hideBundledDummyTestDayTimeMap
        return FormulaLibraryService.bundledLibraryTemplates.first(where: { $0.id == formulaID })
    }

    private var blocks: [DayFormulaBlockTemplate] {
        guard let formula else { return [] }
        let q = queryTrimmed.lowercased()
        guard !q.isEmpty else { return formula.blocks }
        return formula.blocks.filter {
            $0.title.lowercased().contains(q) || $0.type.label.lowercased().contains(q)
        }
    }

    var body: some View {
        Group {
            if let formula {
                List {
                    if blocks.isEmpty {
                        ContentUnavailableView(
                            formula.blocks.isEmpty ? "No blocks" : "No results",
                            systemImage: formula.blocks.isEmpty ? "square.dashed" : "magnifyingglass",
                            description: Text(
                                formula.blocks.isEmpty
                                    ? "This TimeMap has no block rows."
                                    : "Try a different search."
                            )
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        Section {
                            ForEach(blocks) { block in
                                HStack(spacing: CueInSpacing.md) {
                                    Image(systemName: block.timelineGlyph ?? block.type.icon)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(CueInColors.textSecondary)
                                        .frame(width: 32, height: 32)
                                        .background(CueInColors.surfaceSecondary.opacity(0.75), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(block.title)
                                            .font(CueInTypography.bodyMedium)
                                            .foregroundStyle(CueInColors.textPrimary)
                                            .lineLimit(2)
                                        Text(ScheduleBlockFormat.durationLabel(minutes: block.durationMinutes))
                                            .font(CueInTypography.micro)
                                            .foregroundStyle(CueInColors.textTertiary)
                                    }
                                    Spacer(minLength: 0)
                                    Button {
                                        onInsertBlock(block)
                                    } label: {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 22, weight: .semibold))
                                            .foregroundStyle(CueInColors.accentFocus)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(CueInColors.background)
                .navigationTitle(formula.name)
                .cueInNavigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, prompt: "Search blocks")
            } else {
                ContentUnavailableView(
                    "TimeMap unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This layout is no longer in the library.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CueInColors.background)
                .navigationTitle("Blocks")
                .cueInNavigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

// MARK: - TimeMap editor (library)

private struct LibraryIdentifiedBlockID: Identifiable, Hashable {
    let id: UUID
}

/// Snapshot for block editor sheet (matches ``TodayView``’s ``BlockEditSheetItem`` pattern).
private struct LibraryBlockEditSheetItem: Identifiable {
    let id: UUID
    let blockID: UUID
    var block: DayBlock

    init(block: DayBlock) {
        self.id = UUID()
        self.blockID = block.id
        self.block = block
    }
}

private struct LibraryTimeMapEditorView: View {
    /// When `nil`, seeds a new user TimeMap. When set, opens that layout for editing.
    let editingFormulaID: UUID?
    @Binding var libraryEpoch: Int
    let onDismissLibrary: () -> Void

    @Bindable private var viewModel = TodayViewModel.shared

    @State private var didSeedSession = false
    @State private var dayModeBeforeEditor: DayEngineMode?
    @State private var draggedScheduleBlockID: UUID?
    @State private var blockTitleEdit: LibraryBlockEditSheetItem?
    @State private var blockAddTask: LibraryIdentifiedBlockID?
    @State private var blockDeleteConfirm: LibraryIdentifiedBlockID?
    @State private var isJiggleRearrangeMode = false
    @State private var showFormulaScheduleSaveSheet = false
    @State private var showBlockLibrary = false
    @State private var showMoreAddOptions = false
    @State private var showPutOnRunPageConfirm = false

    @AppStorage(TodayDisplayPreferences.showScheduleStartTime) private var showScheduleStartTime = true
    @AppStorage(TodayDisplayPreferences.showScheduleDuration) private var showScheduleDuration = false
    @AppStorage(TodayDisplayPreferences.showScheduleTimeRange) private var showScheduleTimeRange = false
    @AppStorage(TodayDisplayPreferences.scheduleDesign) private var scheduleDesignRaw = TodayDisplayPreferences.ScheduleDesign.glass.rawValue
    @AppStorage(TodayDisplayPreferences.canvasDotsBackground) private var canvasDotsBackground = false
    @AppStorage(TodayDisplayPreferences.scheduleBlockTimerStyle) private var scheduleBlockTimerStyleRaw
        = TodayDisplayPreferences.ScheduleBlockTimerStyle.ring.rawValue
    @AppStorage(TodayDisplayPreferences.scheduleBlockTimerShowsSeconds) private var scheduleBlockTimerShowsSeconds = false

    private var scheduleDesign: TodayDisplayPreferences.ScheduleDesign {
        TodayDisplayPreferences.migratedScheduleDesign(from: scheduleDesignRaw)
    }

    private var scheduleBlockTimerStyle: TodayDisplayPreferences.ScheduleBlockTimerStyle {
        TodayDisplayPreferences.migratedScheduleBlockTimerStyle(from: scheduleBlockTimerStyleRaw)
    }

    var body: some View {
        ZStack {
            Group {
                if canvasDotsBackground {
                    CanvasDotsBackgroundView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    CueInColors.background
                }
            }
            .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: CueInSpacing.md) {
                    editorChromeStrip

                    if viewModel.isFormulaPreviewing,
                       viewModel.hasFormulaTemplate,
                       !viewModel.shouldShowScheduleEmptyCallout {
                        FormulaSchedulePreviewStatsBar(
                            blocks: viewModel.todayScheduleBlocks,
                            showsSaveButton: viewModel.isFormulaPreviewScheduleDirty,
                            onSave: { showFormulaScheduleSaveSheet = true }
                        )
                        .padding(.horizontal, CueInSpacing.screenHorizontal)
                    }

                    if viewModel.shouldShowScheduleEmptyCallout {
                        ScheduleEmptyCalloutView()
                    } else {
                        ScheduleBlockTimelineView(
                            blocks: viewModel.todayScheduleBlocks,
                            currentBlockID: viewModel.currentBlockID,
                            scheduleDesign: scheduleDesign,
                            useCanvasLiquidGlass: canvasDotsBackground,
                            frozenLiveProgressDate: viewModel.formulaSchedulePausedAt,
                            showsScheduledTime: false,
                            showsStartTime: showScheduleStartTime,
                            showsDuration: showScheduleDuration,
                            showsTimeRange: showScheduleTimeRange,
                            showsFinishControl: false,
                            showsCompletedToggle: viewModel.isFormulaMode,
                            isLiveRun: false,
                            timerStyle: scheduleBlockTimerStyle,
                            showsTimerSeconds: scheduleBlockTimerShowsSeconds,
                            draggedBlockID: $draggedScheduleBlockID,
                            canRearrangeBlock: { blockID in
                                viewModel.canRearrangeFormulaBlock(blockID: blockID)
                            },
                            canUseBlockContextMenu: { blockID in
                                viewModel.canUseBlockContextMenu(blockID: blockID)
                            },
                            canDeleteFromContextMenu: { blockID in
                                viewModel.canDeleteFormulaBlock(blockID: blockID)
                            },
                            onMoveBlock: { sourceID, targetID in
                                viewModel.moveFormulaBlock(sourceID: sourceID, before: targetID)
                            },
                            onToggleTask: { blockID, taskID in
                                viewModel.toggleTask(blockID: blockID, taskID: taskID)
                            },
                            onCompleteBlock: { blockID in
                                viewModel.completeBlock(blockID: blockID)
                            },
                            onFinishBlockKeepingPending: { blockID in
                                viewModel.finishBlockKeepingPending(blockID: blockID)
                            },
                            onRevertCompletedBlock: { blockID in
                                viewModel.revertCompletedBlock(blockID: blockID)
                            },
                            onContextEdit: { block in
                                blockTitleEdit = LibraryBlockEditSheetItem(block: block)
                            },
                            onContextAddTask: { blockID in
                                blockAddTask = LibraryIdentifiedBlockID(id: blockID)
                            },
                            onContextRearrange: { _ in
                                isJiggleRearrangeMode = true
                            },
                            onContextDelete: { blockID in
                                blockDeleteConfirm = LibraryIdentifiedBlockID(id: blockID)
                            },
                            onSwipeCommitDelete: { blockID in
                                viewModel.deleteFormulaBlock(blockID: blockID)
                            },
                            isJiggleRearrangeMode: isJiggleRearrangeMode
                        )
                    }
                }
                .padding(.bottom, CueInLayout.scrollBottomInset)
            }
            .scrollDisabled(draggedScheduleBlockID != nil)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                bottomPlusControl
                    .padding(.trailing, CueInSpacing.screenHorizontal)
                    .padding(.bottom, 6)
            }
            .padding(.top, 4)
            .background(
                LinearGradient(
                    colors: [CueInColors.background.opacity(0), CueInColors.background.opacity(0.92)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
            )
        }
        .navigationTitle(viewModel.formulaScheduleNavigationTitle)
        .cueInNavigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Select") {
                    showPutOnRunPageConfirm = true
                }
                .fontWeight(.semibold)
                .foregroundStyle(CueInColors.textPrimary)
                .disabled(viewModel.selectedFormulaID == nil)
            }
            ToolbarItemGroup(placement: CueInToolbarPlacement.topBarTrailing) {
                if isJiggleRearrangeMode {
                    Button("Done") { isJiggleRearrangeMode = false }
                        .fontWeight(.semibold)
                        .foregroundStyle(CueInColors.textPrimary)
                } else if viewModel.isFormulaPreviewScheduleDirty {
                    Button("Save") { showFormulaScheduleSaveSheet = true }
                        .fontWeight(.semibold)
                        .foregroundStyle(CueInColors.textPrimary)
                }
            }
        }
        .alert(
            "Put on run page?",
            isPresented: $showPutOnRunPageConfirm
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Put on run page") {
                if let id = viewModel.selectedFormulaID {
                    LibraryView.applySavedSchedule(id: id)
                    onDismissLibrary()
                }
            }
        } message: {
            let name = viewModel.selectedFormula?.name ?? "this TimeMap"
            Text("Put «\(name)» on the run page?")
        }
        .onAppear {
            guard !didSeedSession else { return }
            dayModeBeforeEditor = viewModel.dayEngineMode
            if viewModel.dayEngineMode != .formulaBased {
                viewModel.setDayEngineMode(.formulaBased)
            }
            if let fid = editingFormulaID {
                viewModel.reloadAvailableFormulasFromLibrary()
                viewModel.selectFormula(fid)
            } else {
                viewModel.createNewUserAlgorithmFromRoutineTemplate()
            }
            didSeedSession = true
        }
        .onDisappear {
            if let prior = dayModeBeforeEditor, prior != .formulaBased {
                viewModel.setDayEngineMode(prior)
            }
            libraryEpoch += 1
        }
        .sheet(isPresented: $showFormulaScheduleSaveSheet) {
            let seed = viewModel.formulaScheduleSaveSheetSeed
            FormulaScheduleSaveSheet(
                initialName: seed.name,
                initialSymbol: seed.symbol,
                initialSummary: seed.summary,
                allowsUpdateExisting: viewModel.isSelectedFormulaUserSavedSchedule,
                scheduleIDExcludedWhenUpdating: viewModel.selectedFormulaID,
                onCancel: { showFormulaScheduleSaveSheet = false },
                onCommit: { name, symbol, summary, intent in
                    if viewModel.saveCurrentPreviewSchedule(
                        name: name,
                        symbol: symbol,
                        summary: summary,
                        intent: intent
                    ) {
                        showFormulaScheduleSaveSheet = false
                    } else {
                        CueInToastCenter.shared.showWarning(
                            icon: "text.badge.xmark",
                            title: "Name already used",
                            message: "That schedule name is taken. Pick another name."
                        )
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .sheet(item: $blockTitleEdit) { item in
            ScheduleBlockEditSheet(
                block: item.block,
                availableScopes: viewModel.scheduleMakerTaskScopes,
                onSave: { draft in
                    viewModel.applyFormulaBlockEdits(blockID: item.blockID, draft: draft)
                    blockTitleEdit = nil
                },
                onCancel: { blockTitleEdit = nil }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .sheet(item: $blockAddTask) { box in
            AddTaskToBlockSheet(
                onAdd: { text in
                    viewModel.addTemplateTaskToFormulaBlock(blockID: box.id, title: text)
                    blockAddTask = nil
                },
                onCancel: { blockAddTask = nil }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .sheet(isPresented: $showBlockLibrary) {
            BlockTemplateLibrarySheet(
                onPick: { template in
                    _ = viewModel.insertFormulaBlock(from: template)
                    showBlockLibrary = false
                },
                onDismiss: { showBlockLibrary = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .sheet(isPresented: $showMoreAddOptions) {
            CueInBottomSheet(title: "Add block", onDismiss: { showMoreAddOptions = false }) {
                VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                    SheetActionRow(
                        icon: "rectangle.stack.fill",
                        title: "Time block",
                        subtitle: "45 min focus slice"
                    ) {
                        showMoreAddOptions = false
                        viewModel.insertFormulaBlock(
                            title: "New Block",
                            type: .focus,
                            flowMode: .blocking,
                            durationMinutes: 45
                        )
                    }
                    SheetActionRow(
                        icon: "books.vertical.fill",
                        title: "From block library",
                        subtitle: "Saved shapes and samples"
                    ) {
                        showMoreAddOptions = false
                        showBlockLibrary = true
                    }
                    SheetActionRow(
                        icon: "repeat",
                        title: "Routine block",
                        subtitle: "Repeatable routine slice"
                    ) {
                        showMoreAddOptions = false
                        viewModel.insertFormulaBlock(
                            title: "Routine Block",
                            type: .routine,
                            flowMode: .blocking,
                            durationMinutes: 30,
                            tasks: [
                                DayTask(title: "First step", isPrimary: true, isRepeating: true)
                            ],
                            isRepeatable: true
                        )
                    }
                    SheetActionRow(
                        icon: "bolt.fill",
                        title: "Quick item",
                        subtitle: "Small flowing slice"
                    ) {
                        showMoreAddOptions = false
                        viewModel.insertFormulaBlock(
                            title: "Quick Item",
                            type: .mini,
                            flowMode: .flowing,
                            durationMinutes: 10
                        )
                    }
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .confirmationDialog(
            "Delete this block?",
            isPresented: Binding(
                get: { blockDeleteConfirm != nil },
                set: { if !$0 { blockDeleteConfirm = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = blockDeleteConfirm?.id {
                    viewModel.deleteFormulaBlock(blockID: id)
                }
                blockDeleteConfirm = nil
            }
            Button("Cancel", role: .cancel) {
                blockDeleteConfirm = nil
            }
        } message: {
            Text("The rest of the day will be re-timed. This can’t be undone.")
        }
    }

    private var editorChromeStrip: some View {
        HStack(spacing: CueInSpacing.sm) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CueInColors.textTertiary)
            Text("Layout editor · changes stay in preview until you Save")
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
        .padding(.vertical, CueInSpacing.sm)
        .background(CueInColors.surfacePrimary.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(CueInColors.cardBorder.opacity(0.55), lineWidth: 0.5)
        )
        .padding(.horizontal, CueInSpacing.screenHorizontal)
    }

    @ViewBuilder
    private var bottomPlusControl: some View {
        #if os(iOS)
        FloatingPlusButton(
            onTap: {
                viewModel.insertFormulaBlock(
                    title: "New Block",
                    type: .focus,
                    flowMode: .blocking,
                    durationMinutes: 45
                )
            },
            onLongPress: {
                showMoreAddOptions = true
            },
            accessibilityLabelText: "Add time block",
            accessibilityHintOverride: "Tap to add a block. Hold for more insert options."
        )
        #else
        Menu {
            Button("Time block (45m)") {
                viewModel.insertFormulaBlock(
                    title: "New Block",
                    type: .focus,
                    flowMode: .blocking,
                    durationMinutes: 45
                )
            }
            Button("Block library…") { showBlockLibrary = true }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(CueInColors.accentFocus)
        }
        #endif
    }
}

// MARK: - Small helpers

private struct IdentifiableUUID: Identifiable {
    let id: UUID
}
