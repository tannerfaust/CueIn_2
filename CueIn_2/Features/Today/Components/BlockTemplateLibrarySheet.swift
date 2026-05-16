import SwiftUI

// MARK: - BlockTemplateLibrarySheet
/// Pick a **block** shape: your saved copies, or individual blocks from bundled sample days (not whole schedules).

private struct LibraryEntry: Identifiable {
    let id: String
    let block: DayFormulaBlockTemplate
    /// Short label: `Saved` or the sample day name.
    let badge: String
    let canDelete: Bool
}

struct BlockTemplateLibrarySheet: View {
    let onPick: (DayFormulaBlockTemplate) -> Void
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var savedLibraryEpoch = 0

    private var queryTrimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var savedBlocks: [DayFormulaBlockTemplate] {
        _ = savedLibraryEpoch
        let all = FormulaLibraryService.customBlockPresets()
        let q = queryTrimmed.lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { $0.title.lowercased().contains(q) }
    }

    private func exampleBlocks(in formula: DayFormulaTemplate) -> [DayFormulaBlockTemplate] {
        let q = queryTrimmed.lowercased()
        guard !q.isEmpty else { return formula.blocks }
        return formula.blocks.filter { block in
            block.title.lowercased().contains(q) || formula.name.lowercased().contains(q)
        }
    }

    /// Flat list: saved first, then every visible example block (no nested sections).
    private var entries: [LibraryEntry] {
        var rows: [LibraryEntry] = []
        for b in savedBlocks {
            rows.append(
                LibraryEntry(
                    id: "saved-\(b.id.uuidString)",
                    block: b,
                    badge: "Saved",
                    canDelete: true
                )
            )
        }
        for formula in FormulaLibraryService.allSchedules {
            for b in exampleBlocks(in: formula) {
                rows.append(
                    LibraryEntry(
                        id: "sample-\(formula.id.uuidString)-\(b.id.uuidString)",
                        block: b,
                        badge: formula.name,
                        canDelete: false
                    )
                )
            }
        }
        return rows
    }

    private var searchMissesEverything: Bool {
        guard !queryTrimmed.isEmpty else { return false }
        return entries.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                if searchMissesEverything {
                    Section {
                        Text("No matching blocks")
                            .font(CueInTypography.caption)
                            .foregroundStyle(CueInColors.textTertiary)
                    }
                } else {
                    Section {
                        if savedBlocks.isEmpty, queryTrimmed.isEmpty {
                            Text("Nothing saved yet")
                                .font(CueInTypography.micro)
                                .foregroundStyle(CueInColors.textTertiary)
                                .listRowBackground(Color.clear)
                        }
                        ForEach(entries) { entry in
                            entryRow(entry)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowBackground(rowBackground)
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .trailing, allowsFullSwipe: entry.canDelete) {
                                    if entry.canDelete {
                                        Button(role: .destructive) {
                                            FormulaLibraryService.removeCustomBlockPreset(id: entry.block.id)
                                            savedLibraryEpoch += 1
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                        }
                    } header: {
                        Text("Blocks")
                            .font(CueInTypography.captionMedium)
                            .foregroundStyle(CueInColors.textSecondary)
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .searchable(text: $query, prompt: "Search blocks")
            .navigationTitle("Block library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDismiss)
                        .foregroundStyle(CueInColors.textSecondary)
                }
            }
            .background(CueInColors.background)
            .onAppear {
                savedLibraryEpoch += 1
            }
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(CueInColors.surfacePrimary.opacity(0.55))
    }

    private func entryRow(_ entry: LibraryEntry) -> some View {
        Button {
            onPick(entry.block)
        } label: {
            HStack(alignment: .top, spacing: CueInSpacing.md) {
                Image(systemName: entry.block.resolvedTimelineGlyph)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CueInColors.textSecondary)
                    .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.block.title)
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(entry.badge)
                        .font(CueInTypography.micro)
                        .foregroundStyle(CueInColors.textTertiary)
                    Text(summary(for: entry.block))
                        .font(CueInTypography.micro)
                        .foregroundStyle(CueInColors.textSecondary.opacity(0.9))
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func summary(for block: DayFormulaBlockTemplate) -> String {
        let duration = ScheduleBlockFormat.durationLabel(minutes: max(block.durationMinutes, 1))
        if block.pinsToClock, let mins = block.fixedClockMinutesFromDayStart {
            let clock = ScheduleBlockFormat.shortClockLabel(minutesFromMidnight: mins)
            return "\(duration) · pinned \(clock) · \(sourceLine(block))"
        }
        return "\(duration) · \(sourceLine(block))"
    }

    private func sourceLine(_ block: DayFormulaBlockTemplate) -> String {
        switch block.taskSource {
        case .templateTasks:
            let n = block.tasks.count
            return n == 0 ? "Tasks · none" : "Tasks · \(n)"
        case .executionFill:
            return "Pool · \(block.fillRule?.displayLabel ?? "Any task")"
        case .noTasks:
            return "No tasks"
        }
    }
}

#Preview {
    BlockTemplateLibrarySheet(onPick: { _ in }, onDismiss: {})
        .cueInPreferredColorScheme()
}
