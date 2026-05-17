import SwiftUI

// MARK: - FormulaPickerSheet
/// Minimal picker for selecting which schedule drives the Today runtime.
///
/// **Sheet blur:** The frosted “Liquid Glass” / system sheet is the *default* when the presenter
/// does **not** use `.presentationBackground` with an opaque `Color` (that flattens the sheet).

struct FormulaPickerSheet: View {
    let formulas: [DayFormulaTemplate]
    let selectedFormulaID: UUID?
    let onSelect: (UUID) -> Void
    let onCreate: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: CueInSpacing.md) {
                    Text("Choose the schedule that should drive today.")
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textSecondary)
                        .padding(.horizontal, CueInSpacing.screenHorizontal)
                        .padding(.top, CueInSpacing.sm)

                    VStack(spacing: CueInSpacing.md) {
                        ForEach(formulas) { formula in
                            Button {
                                onSelect(formula.id)
                            } label: {
                                CueInCard(
                                    surface: selectedFormulaID == formula.id
                                        ? CueInColors.surfaceSecondary
                                        : CueInColors.surfacePrimary
                                ) {
                                    VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                                        HStack(alignment: .top, spacing: CueInSpacing.md) {
                                            Image(systemName: formula.symbol)
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundStyle(CueInColors.textSecondary)
                                                .frame(width: 34, height: 34)
                                                .background(CueInColors.surfaceTertiary)
                                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(formula.name)
                                                    .font(CueInTypography.bodyMedium)
                                                    .foregroundStyle(CueInColors.textPrimary)

                                                Text(formula.summary)
                                                    .font(CueInTypography.caption)
                                                    .foregroundStyle(CueInColors.textSecondary)
                                                    .lineLimit(2)
                                            }

                                            Spacer(minLength: 0)

                                            if selectedFormulaID == formula.id {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundStyle(CueInColors.textPrimary)
                                            }
                                        }

                                        HStack(spacing: CueInSpacing.sm) {
                                            metric(text: formula.targetDurationLabel)
                                            metric(text: "\(formula.blockCount) blocks")
                                            if formula.executionFilledBlockCount > 0 {
                                                metric(text: "\(formula.executionFilledBlockCount) dynamic")
                                            } else {
                                                metric(text: "\(formula.totalTaskCount) tasks")
                                            }
                                        }

                                        Text(formula.previewTitles)
                                            .font(CueInTypography.micro)
                                            .foregroundStyle(CueInColors.textTertiary)
                                            .lineLimit(2)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, CueInSpacing.screenHorizontal)
                    .padding(.bottom, CueInSpacing.xl)
                }
            }
            .background(CueInColors.background)
            .navigationTitle("Schedules")
            .cueInNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onCreate()
                    } label: {
                        Label("Make", systemImage: "plus")
                    }
                }
            }
        }
    }

    private func metric(text: String) -> some View {
        Text(text)
            .font(CueInTypography.micro)
            .foregroundStyle(CueInColors.textSecondary)
            .padding(.horizontal, CueInSpacing.sm)
            .padding(.vertical, 6)
            .background(CueInColors.surfaceTertiary)
            .clipShape(Capsule())
    }
}
