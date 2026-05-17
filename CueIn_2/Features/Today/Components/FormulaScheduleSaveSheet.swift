import SwiftUI

// MARK: - FormulaScheduleSaveIntent

enum FormulaScheduleSaveIntent: Hashable {
    case saveAsNew
    case updateExisting
}

// MARK: - FormulaSchedulePreviewStatsBar

/// Preview header: total planned duration, optional save when the schedule has unsaved block edits.
struct FormulaSchedulePreviewStatsBar: View {
    let blocks: [DayBlock]
    let showsSaveButton: Bool
    let onSave: () -> Void

    private var totalMinutes: Int {
        blocks.reduce(0) { $0 + max($1.durationMinutes, 1) }
    }

    var body: some View {
        HStack(alignment: .center, spacing: CueInSpacing.md) {
            Text(ScheduleBlockFormat.durationLabel(minutes: totalMinutes))
                .font(CueInTypography.title)
                .foregroundStyle(CueInColors.textPrimary)
                .monospacedDigit()
                .accessibilityLabel("Schedule duration, \(ScheduleBlockFormat.durationLabel(minutes: totalMinutes))")

            Spacer(minLength: 0)

            if showsSaveButton {
                Button("Save", action: onSave)
                    .font(CueInTypography.captionMedium)
                    .foregroundStyle(CueInColors.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(CueInColors.surfaceSecondary, in: Capsule(style: .continuous))
                    .buttonStyle(.plain)
                    .accessibilityHint("Name, icon, and save to your library.")
            }
        }
    }
}

// MARK: - FormulaScheduleSaveSheet

/// Small sheet to name / icon a schedule, with update vs. duplicate when editing a user-saved template.
struct FormulaScheduleSaveSheet: View {
    let initialName: String
    let initialSymbol: String
    let initialSummary: String
    let allowsUpdateExisting: Bool
    /// When updating the current user schedule, its id is excluded from the “unique name” check so the same name can stay.
    let scheduleIDExcludedWhenUpdating: UUID?
    let onCancel: () -> Void
    let onCommit: (String, String, String, FormulaScheduleSaveIntent) -> Void

    @State private var name: String
    @State private var symbol: String
    @State private var summary: String
    @State private var nameValidationMessage: String?

    private let symbols = [
        "calendar", "sparkles", "bolt.fill", "sun.max.fill", "moon.fill",
        "heart.text.square.fill", "square.stack.fill", "leaf.fill", "book.fill",
        "figure.run", "cup.and.saucer.fill"
    ]

    init(
        initialName: String,
        initialSymbol: String,
        initialSummary: String,
        allowsUpdateExisting: Bool,
        scheduleIDExcludedWhenUpdating: UUID?,
        onCancel: @escaping () -> Void,
        onCommit: @escaping (String, String, String, FormulaScheduleSaveIntent) -> Void
    ) {
        self.initialName = initialName
        self.initialSymbol = initialSymbol
        self.initialSummary = initialSummary
        self.allowsUpdateExisting = allowsUpdateExisting
        self.scheduleIDExcludedWhenUpdating = scheduleIDExcludedWhenUpdating
        self.onCancel = onCancel
        self.onCommit = onCommit
        _name = State(initialValue: initialName)
        _symbol = State(initialValue: initialSymbol)
        _summary = State(initialValue: initialSummary)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canCommit: Bool { !trimmedName.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: CueInSpacing.lg) {
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
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(CueInColors.textPrimary)
                                .frame(width: 48, height: 48)
                                .background(CueInColors.surfaceSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Schedule icon")

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Name")
                                .font(CueInTypography.micro)
                                .foregroundStyle(CueInColors.textTertiary)
                            TextField("Schedule name", text: $name)
                                .font(CueInTypography.title)
                                .foregroundStyle(CueInColors.textPrimary)
                                .textInputAutocapitalization(.words)
                        }
                    }

                    if let nameValidationMessage {
                        Text(nameValidationMessage)
                            .font(CueInTypography.caption)
                            .foregroundStyle(CueInColors.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Short description")
                            .font(CueInTypography.micro)
                            .foregroundStyle(CueInColors.textTertiary)
                        TextField("Optional — shown in the library", text: $summary, axis: .vertical)
                            .font(CueInTypography.body)
                            .foregroundStyle(CueInColors.textPrimary)
                            .lineLimit(3...6)
                    }

                    if allowsUpdateExisting {
                        VStack(spacing: CueInSpacing.sm) {
                            Button {
                                validateAndCommit(.updateExisting)
                            } label: {
                                Text("Update “\(initialName)”")
                                    .font(CueInTypography.headline)
                                    .foregroundStyle(CueInColors.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(CueInColors.accentFocus.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(!canCommit)

                            Button {
                                validateAndCommit(.saveAsNew)
                            } label: {
                                Text("Save as new schedule")
                                    .font(CueInTypography.headline)
                                    .foregroundStyle(CueInColors.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(CueInColors.surfaceSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(!canCommit)
                        }
                    } else {
                        Button {
                            validateAndCommit(.saveAsNew)
                        } label: {
                            Text("Save to library")
                                .font(CueInTypography.headline)
                                .foregroundStyle(CueInColors.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(CueInColors.accentFocus.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canCommit)
                    }
                }
                .padding(.horizontal, CueInSpacing.screenHorizontal)
                .padding(.vertical, CueInSpacing.md)
            }
            .background(CueInColors.background)
            .navigationTitle("Save schedule")
            .cueInNavigationBarTitleDisplayMode(.inline)
            .cueInNavigationToolbarColorScheme()
            .onChange(of: name) { _, _ in
                nameValidationMessage = nil
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }

    private func excludedScheduleID(for intent: FormulaScheduleSaveIntent) -> UUID? {
        switch intent {
        case .updateExisting:
            return scheduleIDExcludedWhenUpdating
        case .saveAsNew:
            return nil
        }
    }

    private func validateAndCommit(_ intent: FormulaScheduleSaveIntent) {
        nameValidationMessage = nil
        let trimmed = trimmedName
        guard !trimmed.isEmpty else { return }

        let exclude = excludedScheduleID(for: intent)
        if FormulaLibraryService.existingScheduleConflictingWithName(trimmed, excludingScheduleID: exclude) != nil {
            switch intent {
            case .updateExisting:
                nameValidationMessage = "Another schedule already uses that name. Pick a different name, or keep this schedule’s name to update it in place."
            case .saveAsNew:
                nameValidationMessage = "That name is already taken (including built-in schedules). Enter a new name for this copy."
            }
            return
        }

        onCommit(trimmed, symbol, summary, intent)
    }
}
