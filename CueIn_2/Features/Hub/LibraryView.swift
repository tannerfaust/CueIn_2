import SwiftUI

// MARK: - Library (Hub)

enum LibraryHomeSegment: String, CaseIterable, Identifiable {
    case tasks
    case blocks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tasks: return "Tasks"
        case .blocks: return "Blocks"
        }
    }
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
    @State private var blockSearchQuery = ""

    init(initialSegment: LibraryHomeSegment = .tasks, onRequestDismiss: @escaping () -> Void) {
        self.initialSegment = initialSegment
        self.onRequestDismiss = onRequestDismiss
        _segment = State(initialValue: initialSegment)
    }

    private var searchTrimmed: String {
        blockSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var savedTasks: [TaskItem] {
        tasksStore.tasks
            .filter(\.savesToArchive)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var userSchedules: [DayFormulaTemplate] {
        _ = libraryEpoch
        let base = FormulaLibraryService.customSchedules()
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return filterSchedules(base)
    }

    private var userBlocks: [DayFormulaBlockTemplate] {
        _ = libraryEpoch
        let base = FormulaLibraryService.customBlockPresets()
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return filterUserBlocks(base)
    }

    private var sampleBlockItems: [SampleBlockItem] {
        let rows = FormulaLibraryService.library.flatMap { formula in
            formula.blocks.map { SampleBlockItem(formulaID: formula.id, formulaName: formula.name, block: $0) }
        }
        return filterSamples(rows)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $segment) {
                    ForEach(LibraryHomeSegment.allCases) { seg in
                        Text(seg.title).tag(seg)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, CueInSpacing.screenHorizontal)
                .padding(.vertical, CueInSpacing.sm)

                if segment == .blocks {
                    searchBar
                }

                ScrollView {
                    switch segment {
                    case .tasks:
                        tasksSection
                    case .blocks:
                        blocksHubSection
                    }
                }
                .scrollIndicators(.hidden)
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
        }
        .onAppear { segment = initialSegment }
        .sheet(item: Binding(
            get: { taskEditID.map { IdentifiableUUID(id: $0) } },
            set: { taskEditID = $0?.id }
        )) { wrapped in
            TaskDetailSheet(mode: .edit(wrapped.id), store: tasksStore, onDismiss: { taskEditID = nil })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .alert("Remove this day schedule from your library?", isPresented: Binding(
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
        .alert("Delete this block preset?", isPresented: Binding(
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

    // MARK: Search (Blocks)

    private var searchBar: some View {
        HStack(spacing: CueInSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CueInColors.textTertiary)
            TextField("Search schedules & blocks", text: $blockSearchQuery)
                .font(CueInTypography.body)
                .foregroundStyle(CueInColors.textPrimary)
            if !blockSearchQuery.isEmpty {
                Button {
                    blockSearchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(CueInColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, CueInSpacing.md)
        .padding(.vertical, 10)
        .background(CueInColors.surfacePrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(CueInColors.cardBorder, lineWidth: 0.5)
        )
        .padding(.horizontal, CueInSpacing.screenHorizontal)
        .padding(.bottom, CueInSpacing.sm)
    }

    private func filterSchedules(_ list: [DayFormulaTemplate]) -> [DayFormulaTemplate] {
        let q = searchTrimmed.lowercased()
        guard !q.isEmpty else { return list }
        return list.filter {
            $0.name.lowercased().contains(q)
                || $0.summary.lowercased().contains(q)
                || $0.previewTitles.lowercased().contains(q)
        }
    }

    private func filterUserBlocks(_ list: [DayFormulaBlockTemplate]) -> [DayFormulaBlockTemplate] {
        let q = searchTrimmed.lowercased()
        guard !q.isEmpty else { return list }
        return list.filter { $0.title.lowercased().contains(q) || $0.type.label.lowercased().contains(q) }
    }

    private func filterSamples(_ rows: [SampleBlockItem]) -> [SampleBlockItem] {
        let q = searchTrimmed.lowercased()
        guard !q.isEmpty else { return rows }
        return rows.filter {
            $0.block.title.lowercased().contains(q)
                || $0.formulaName.lowercased().contains(q)
                || $0.block.type.label.lowercased().contains(q)
        }
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

    // MARK: Blocks hub (schedules + separate blocks)

    private var blocksHubSection: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.xl) {
            blockSchedulesSection
            separateBlocksSection
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
        .padding(.top, CueInSpacing.md)
        .padding(.bottom, CueInLayout.scrollBottomInset)
    }

    private var blockSchedulesSection: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            sectionChromeTitle(
                "Block schedules",
                subtitle: "Whole-day layouts you saved. They open as your day on Blocks."
            )

            if userSchedules.isEmpty {
                emptyStatePanel(
                    icon: "rectangle.split.3x1",
                    title: "No saved day layouts",
                    message: "On Blocks, build or edit a day, then save it as a reusable schedule."
                )
            } else {
                GeometryReader { geo in
                    let cardWidth = min(320, max(260, geo.size.width - CueInSpacing.screenHorizontal * 2))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: CueInSpacing.md) {
                            ForEach(userSchedules) { formula in
                                scheduleCarouselCard(formula, width: cardWidth)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .frame(height: 220)
            }
        }
    }

    private func scheduleCarouselCard(_ formula: DayFormulaTemplate, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [
                        CueInColors.surfaceSecondary.opacity(0.95),
                        CueInColors.surfacePrimary.opacity(0.4),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 72)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: formula.symbol)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(CueInColors.textPrimary.opacity(0.85))
                        .padding(CueInSpacing.md)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(formula.name)
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                        .lineLimit(2)
                    HStack(spacing: CueInSpacing.sm) {
                        chip(text: "\(formula.blockCount) blocks", icon: "square.split.2x1")
                        chip(text: formula.targetDurationLabel, icon: "clock")
                    }
                }
                .padding(CueInSpacing.md)
            }

            if !formula.summary.isEmpty {
                Text(formula.summary)
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
                    .lineLimit(2)
                    .padding(.horizontal, CueInSpacing.md)
                    .padding(.bottom, CueInSpacing.sm)
            }

            HStack(spacing: CueInSpacing.sm) {
                Button {
                    Self.applySavedSchedule(id: formula.id)
                    onRequestDismiss()
                    dismiss()
                } label: {
                    Label("Use on Blocks", systemImage: "play.fill")
                        .font(CueInTypography.captionMedium)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(CueInColors.accentFocus)

                Button {
                    schedulePendingDelete = formula
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 40, height: 36)
                }
                .buttonStyle(.bordered)
                .tint(CueInColors.textSecondary)
                .accessibilityLabel("Delete schedule")
            }
            .padding(CueInSpacing.md)
        }
        .frame(width: width, alignment: .leading)
        .background(CueInColors.surfacePrimary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(CueInColors.cardBorder, lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 8)
    }

    private var separateBlocksSection: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.lg) {
            sectionChromeTitle(
                "Separate blocks",
                subtitle: "Single time slices — yours first, then shapes from bundled sample days."
            )

            VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                Text("Your blocks")
                    .font(CueInTypography.captionMedium)
                    .foregroundStyle(CueInColors.textSecondary)

                if userBlocks.isEmpty {
                    subtleEmptyRow("No saved presets yet — save a block from the block editor on Blocks.")
                } else {
                    LazyVStack(spacing: CueInSpacing.sm) {
                        ForEach(userBlocks) { block in
                            separateBlockCard(block: block, sourceLabel: nil, canDelete: true)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                Text("From sample days")
                    .font(CueInTypography.captionMedium)
                    .foregroundStyle(CueInColors.textSecondary)

                if sampleBlockItems.isEmpty {
                    subtleEmptyRow("Bundled sample days will list extractable blocks here.")
                } else {
                    LazyVStack(spacing: CueInSpacing.sm) {
                        ForEach(sampleBlockItems) { item in
                            separateBlockCard(
                                block: item.block,
                                sourceLabel: item.formulaName,
                                canDelete: false
                            )
                        }
                    }
                }
            }
        }
    }

    private func separateBlockCard(
        block: DayFormulaBlockTemplate,
        sourceLabel: String?,
        canDelete: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            HStack(alignment: .top, spacing: CueInSpacing.md) {
                Image(systemName: block.timelineGlyph ?? block.type.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CueInColors.textPrimary)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill(CueInColors.surfaceSecondary.opacity(0.9))
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(block.title)
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                        .lineLimit(2)
                    HStack(spacing: CueInSpacing.sm) {
                        chip(
                            text: ScheduleBlockFormat.durationLabel(minutes: block.durationMinutes),
                            icon: "timer"
                        )
                        chip(text: block.type.label, icon: "square.grid.2x2")
                    }
                    if let sourceLabel {
                        Text(sourceLabel)
                            .font(CueInTypography.micro)
                            .foregroundStyle(CueInColors.textTertiary)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: CueInSpacing.sm) {
                Button {
                    useBlockTemplate(block)
                } label: {
                    Label("Insert on Blocks", systemImage: "plus.circle.fill")
                        .font(CueInTypography.captionMedium)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(CueInColors.accentFocus)

                if canDelete {
                    Button {
                        blockPendingDelete = block
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 40, height: 36)
                    }
                    .buttonStyle(.bordered)
                    .tint(CueInColors.textSecondary)
                    .accessibilityLabel("Delete preset")
                }
            }
        }
        .padding(CueInSpacing.base)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(CueInColors.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(CueInColors.cardBorder.opacity(0.85), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
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

    private func chip(text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(CueInTypography.micro)
        }
        .foregroundStyle(CueInColors.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(CueInColors.surfacePrimary.opacity(0.65), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(CueInColors.divider.opacity(0.5), lineWidth: 0.5)
        )
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

    private func subtleEmptyRow(_ message: String) -> some View {
        Text(message)
            .font(CueInTypography.caption)
            .foregroundStyle(CueInColors.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(CueInSpacing.md)
            .background(CueInColors.surfaceSecondary.opacity(0.25), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

// MARK: - Small helpers

private struct IdentifiableUUID: Identifiable {
    let id: UUID
}
