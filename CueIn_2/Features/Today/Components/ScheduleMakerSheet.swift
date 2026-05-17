import SwiftUI

// MARK: - ScheduleMakerDurationOverview
/// Live total and per-block time shares while building a Blocks schedule (updates as durations change).

private struct ScheduleMakerDurationOverview: View {
    let drafts: [ScheduleBlockDraft]

    private var totalMinutes: Int {
        drafts.reduce(0) { $0 + max($1.durationMinutes, 1) }
    }

    private var executionFillCount: Int {
        drafts.filter { $0.assignsTasks && $0.poolFillEnabled }.count
    }

    private var noTasksCount: Int {
        drafts.filter { !$0.assignsTasks }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: CueInSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total duration")
                        .font(CueInTypography.micro)
                        .foregroundStyle(CueInColors.textTertiary)
                    Text(ScheduleBlockFormat.durationLabel(minutes: totalMinutes))
                        .font(CueInTypography.title)
                        .foregroundStyle(CueInColors.textPrimary)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Blocks")
                        .font(CueInTypography.micro)
                        .foregroundStyle(CueInColors.textTertiary)
                    Text("\(drafts.count)")
                        .font(CueInTypography.title)
                        .foregroundStyle(CueInColors.textPrimary)
                        .monospacedDigit()
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CueInSpacing.sm) {
                    ForEach(drafts) { draft in
                        blockShareChip(draft)
                    }
                }
            }
            .padding(.vertical, 2)

            HStack(spacing: CueInSpacing.sm) {
                metaChip("\(drafts.count) \(drafts.count == 1 ? "block" : "blocks")")
                metaChip(ScheduleBlockFormat.durationLabel(minutes: totalMinutes))
                if executionFillCount > 0 {
                    metaChip("\(executionFillCount) pool fill", tint: CueInColors.accentFocus)
                }
                if noTasksCount > 0 {
                    metaChip("\(noTasksCount) time-only", tint: CueInColors.textTertiary)
                }
            }
        }
        .padding(CueInSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CueInColors.surfacePrimary.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(CueInColors.divider.opacity(0.35), lineWidth: 0.5)
        )
    }

    private func blockShareChip(_ draft: ScheduleBlockDraft) -> some View {
        let m = max(draft.durationMinutes, 1)
        let share = totalMinutes > 0 ? CGFloat(m) / CGFloat(totalMinutes) : 0
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 6) {
            Text(title.isEmpty ? "Untitled" : title)
                .font(CueInTypography.captionMedium)
                .foregroundStyle(title.isEmpty ? CueInColors.textTertiary : CueInColors.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: 160, alignment: .leading)
            Text(ScheduleBlockFormat.durationLabel(minutes: m))
                .font(CueInTypography.micro)
                .foregroundStyle(CueInColors.textSecondary)
                .monospacedDigit()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(CueInColors.surfaceTertiary.opacity(0.55))
                    Capsule(style: .continuous)
                        .fill(CueInColors.accentFocus.opacity(0.55))
                        .frame(width: max(4, geo.size.width * share))
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CueInColors.surfaceSecondary.opacity(0.55))
        )
    }

    private func metaChip(_ text: String, tint: Color? = nil) -> some View {
        Text(text)
            .font(CueInTypography.micro)
            .foregroundStyle(tint ?? CueInColors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(CueInColors.surfaceSecondary.opacity(0.65))
            )
    }
}

// MARK: - ScheduleMakerSheet
/// Minimalist schedule builder.
///
/// Blocks are **horizontal full-width rows** stacked vertically. Tapping a row
/// expands the editor for that block *inline* (accordion), so the control you
/// touch is always the thing you're editing. One row is expanded at a time.
/// Long-press + drag to reorder.

struct ScheduleMakerSheet: View {
    let availableScopes: ScheduleMakerTaskScopes
    let onSave: (DayFormulaTemplate) -> Void
    let onDismiss: () -> Void

    @State private var name = "My Schedule"
    @State private var symbol = "calendar"
    @State private var blocks: [ScheduleBlockDraft] = [ScheduleBlockDraft.routineTemplate()]
    @State private var expandedBlockID: UUID?
    @State private var showBlockLibrary = false
    @State private var scheduleNameConflictMessage: String?

    private let symbols = ["calendar", "sparkles", "bolt.fill", "sun.max.fill", "moon.fill", "heart.text.square.fill"]

    init(
        availableScopes: ScheduleMakerTaskScopes = .empty,
        onSave: @escaping (DayFormulaTemplate) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.availableScopes = availableScopes
        self.onSave = onSave
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CueInColors.background.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: CueInSpacing.lg) {
                        ScheduleMakerDurationOverview(drafts: blocks)
                        headerRow
                        blocksSection
                    }
                    .padding(.horizontal, CueInSpacing.screenHorizontal)
                    .padding(.top, CueInSpacing.md)
                    .padding(.bottom, 112)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { saveBar }
            .onAppear {
                if expandedBlockID == nil {
                    expandedBlockID = blocks.first?.id
                }
            }
            .onChange(of: name) { _, _ in
                scheduleNameConflictMessage = nil
            }
            .navigationTitle("Blocks")
            .cueInNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        commitSaveIfNameAvailable()
                    } label: {
                        Label("Save", systemImage: "plus")
                    }
                    .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showBlockLibrary) {
                BlockTemplateLibrarySheet(
                    onPick: { template in
                        appendBlock(ScheduleBlockDraft(from: template))
                        showBlockLibrary = false
                    },
                    onDismiss: { showBlockLibrary = false }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
            }
        }
    }

    // MARK: - Header (compact)

    private var headerRow: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.xs) {
            HStack(spacing: CueInSpacing.md) {
                Menu {
                    ForEach(symbols, id: \.self) { candidate in
                        Button {
                            symbol = candidate
                        } label: {
                            Label(candidate, systemImage: candidate)
                        }
                    }
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CueInColors.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(CueInColors.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                TextField("Schedule name", text: $name)
                    .font(CueInTypography.title)
                    .foregroundStyle(CueInColors.textPrimary)
            }

            if let scheduleNameConflictMessage {
                Text(scheduleNameConflictMessage)
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Blocks section

    private var blocksSection: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            HStack {
                Text("Blocks")
                    .font(CueInTypography.captionMedium)
                    .foregroundStyle(CueInColors.textSecondary)
                Spacer()
                Button {
                    showBlockLibrary = true
                } label: {
                    Image(systemName: "square.stack.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CueInColors.textSecondary)
                        .frame(width: 36, height: 32)
                        .background(Capsule(style: .continuous).fill(CueInColors.surfaceSecondary))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Block library")
                addBlockMenu
            }

            LazyVStack(spacing: CueInSpacing.xs) {
                ForEach($blocks) { $block in
                    BlockRow(
                        block: $block,
                        isExpanded: expandedBlockID == block.id,
                        canDelete: blocks.count > 1,
                        availableScopes: availableScopes,
                        onToggle: { toggleExpansion(for: block.id) },
                        onDelete: { removeBlock(block.id) },
                        onDuplicate: { duplicateBlock(block.id) },
                        onMoveUp: canMoveUp(block.id) ? { moveBlock(id: block.id, offset: -1) } : nil,
                        onMoveDown: canMoveDown(block.id) ? { moveBlock(id: block.id, offset: 1) } : nil
                    )
                }
            }
        }
    }

    private var addBlockMenu: some View {
        Menu {
            Button { appendBlock(ScheduleBlockDraft.routineTemplate()) } label: {
                Label("Routine block", systemImage: "checklist")
            }
            Button { appendBlock(ScheduleBlockDraft.executionFillTemplate()) } label: {
                Label("Pool fill block", systemImage: "sparkles")
            }
            Button { appendBlock(ScheduleBlockDraft.noTasksTemplate()) } label: {
                Label("Time block (no tasks)", systemImage: "circle.dashed")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                Text("Add")
                    .font(CueInTypography.micro)
            }
            .foregroundStyle(CueInColors.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule(style: .continuous).fill(CueInColors.surfaceSecondary))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Save bar

    private var saveBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(CueInColors.divider).frame(height: 0.5)
            Button {
                commitSaveIfNameAvailable()
            } label: {
                HStack {
                    Text("Save schedule")
                    Spacer()
                    Text(ScheduleBlockFormat.durationLabel(minutes: totalMinutes))
                        .foregroundStyle(CueInColors.background.opacity(0.5))
                }
                .font(CueInTypography.bodyMedium)
                .foregroundStyle(CueInColors.background)
                .padding(.horizontal, CueInSpacing.lg)
                .padding(.vertical, CueInSpacing.md)
                .background(CueInColors.textPrimary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, CueInSpacing.screenHorizontal)
                .padding(.vertical, CueInSpacing.md)
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.45)
            .background(CueInColors.background.opacity(0.96))
        }
    }

    // MARK: - Actions

    private func commitSaveIfNameAvailable() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if FormulaLibraryService.existingScheduleConflictingWithName(trimmed, excludingScheduleID: nil) != nil {
            scheduleNameConflictMessage = "That name is already used. Change the name to save this schedule."
            return
        }
        scheduleNameConflictMessage = nil
        onSave(makeFormula())
    }

    private func toggleExpansion(for id: UUID) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            expandedBlockID = expandedBlockID == id ? nil : id
        }
    }

    private func appendBlock(_ block: ScheduleBlockDraft) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            blocks.append(block)
            expandedBlockID = block.id
        }
    }

    private func removeBlock(_ id: UUID) {
        guard blocks.count > 1 else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            blocks.removeAll { $0.id == id }
            if expandedBlockID == id { expandedBlockID = nil }
        }
    }

    private func duplicateBlock(_ id: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            var copy = blocks[index]
            copy.id = UUID()
            copy.tasks = copy.tasks.map { var t = $0; t.id = UUID(); return t }
            blocks.insert(copy, at: index + 1)
            expandedBlockID = copy.id
        }
    }

    private func moveBlock(id: UUID, offset: Int) {
        guard let currentIndex = blocks.firstIndex(where: { $0.id == id }) else { return }
        let newIndex = currentIndex + offset
        guard blocks.indices.contains(newIndex) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            let block = blocks.remove(at: currentIndex)
            blocks.insert(block, at: newIndex)
        }
    }

    private func canMoveUp(_ id: UUID) -> Bool {
        (blocks.firstIndex(where: { $0.id == id }) ?? 0) > 0
    }

    private func canMoveDown(_ id: UUID) -> Bool {
        guard let idx = blocks.firstIndex(where: { $0.id == id }) else { return false }
        return idx < blocks.count - 1
    }

    // MARK: - Derived

    private var totalMinutes: Int {
        blocks.reduce(0) { $0 + max($1.durationMinutes, 1) }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && blocks.contains { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func makeFormula() -> DayFormulaTemplate {
        let cleanBlocks = blocks
            .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { $0.toFormulaBlockTemplate() }

        return DayFormulaTemplate(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            symbol: symbol,
            summary: "\(Self.frameCountLabel(cleanBlocks.count)) · \(ScheduleBlockFormat.durationLabel(minutes: totalMinutes))",
            targetDurationMinutes: max(totalMinutes, 5),
            rules: [],
            blocks: cleanBlocks
        )
    }

    private static func frameCountLabel(_ count: Int) -> String {
        "\(count) \(count == 1 ? "block" : "blocks")"
    }
}

// MARK: - BlockRow

private struct BlockRow: View {
    @Binding var block: ScheduleBlockDraft
    let isExpanded: Bool
    let canDelete: Bool
    let availableScopes: ScheduleMakerTaskScopes
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            collapsedHeader
                .contentShape(Rectangle())
                .onTapGesture(perform: onToggle)

            if isExpanded {
                expandedEditor
                    .padding(.top, CueInSpacing.md)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }
        }
        .padding(.horizontal, CueInSpacing.md)
        .padding(.vertical, isExpanded ? CueInSpacing.md : 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isExpanded ? CueInColors.surfaceSecondary.opacity(0.62) : CueInColors.surfacePrimary.opacity(0.92))
        )
    }

    private var collapsedHeader: some View {
        HStack(spacing: CueInSpacing.md) {
            Image(systemName: block.resolvedTimelineGlyph)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CueInColors.textPrimary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(CueInColors.surfaceTertiary.opacity(0.6))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(block.title.isEmpty ? "Untitled" : block.title)
                    .font(CueInTypography.bodyMedium)
                    .foregroundStyle(block.title.isEmpty ? CueInColors.textTertiary : CueInColors.textPrimary)
                    .lineLimit(1)

                Text(block.subtitleLine)
                    .font(CueInTypography.micro)
                    .foregroundStyle(CueInColors.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: CueInSpacing.sm)

            Text(ScheduleBlockFormat.durationLabel(minutes: block.durationMinutes))
                .font(CueInTypography.captionMedium)
                .foregroundStyle(CueInColors.textSecondary)
                .monospacedDigit()

            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CueInColors.textTertiary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .animation(.easeInOut(duration: 0.2), value: isExpanded)
        }
    }

    private var expandedEditor: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.lg) {
            Divider().overlay(CueInColors.divider)

            ScheduleBlockEditorForm(
                block: $block,
                availableScopes: availableScopes,
                allowsPoolFillSource: true,
                showsAnchorNotice: false,
                allowsFixedClockEdit: true,
                createdTasksGoToToday: false,
                onSavePreset: {
                    let trimmed = block.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return false }
                    return FormulaLibraryService.saveCustomBlockPreset(block.toFormulaBlockTemplate())
                }
            )

            actionRow
        }
    }

    private var actionRow: some View {
        HStack(spacing: CueInSpacing.xs) {
            if let onMoveUp {
                iconButton(systemName: "arrow.up", action: onMoveUp)
            }
            if let onMoveDown {
                iconButton(systemName: "arrow.down", action: onMoveDown)
            }
            Spacer()
            iconButton(systemName: "plus.square.on.square", action: onDuplicate)
            if canDelete {
                iconButton(systemName: "trash", tint: CueInColors.danger.opacity(0.8), action: onDelete)
            }
        }
    }

    private func iconButton(systemName: String, tint: Color = CueInColors.textSecondary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 30)
                .background(CueInColors.surfacePrimary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ScheduleMakerSheet(
        onSave: { _ in },
        onDismiss: {}
    )
    .cueInPreferredColorScheme()
}
