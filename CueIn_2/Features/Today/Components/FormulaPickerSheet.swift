import SwiftUI

// MARK: - FormulaPickerSheet
/// Minimal picker for selecting which TimeMap drives the Today runtime.
///
/// **Sheet blur:** The frosted “Liquid Glass” / system sheet is the *default* when the presenter
/// does **not** use `.presentationBackground` with an opaque `Color` (that flattens the sheet).

struct FormulaPickerSheet: View {
    let formulas: [DayFormulaTemplate]
    let selectedFormulaID: UUID?
    let onSelect: (UUID) -> Void
    /// Starts a blank TimeMap on Today (saved starter + selected). Omit to hide the toolbar control.
    let onNewTimeMap: (() -> Void)?
    let onDismiss: () -> Void

    init(
        formulas: [DayFormulaTemplate],
        selectedFormulaID: UUID?,
        onSelect: @escaping (UUID) -> Void,
        onNewTimeMap: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.formulas = formulas
        self.selectedFormulaID = selectedFormulaID
        self.onSelect = onSelect
        self.onNewTimeMap = onNewTimeMap
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: CueInSpacing.md) {
                    Text("Choose the TimeMap that should drive today.")
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
                                            metric(text: "\(formula.blockCount) time blocks")
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
            .navigationTitle("Choose TimeMap")
            .cueInNavigationBarTitleDisplayMode(.inline)
            // One trailing toolbar group avoids UIKit zero-width `ItemWrapperView` constraint
            // conflicts seen when mixing `.cancellationAction` + `.confirmationAction` with `Label`.
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let onNewTimeMap {
                        Button(action: onNewTimeMap) {
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("New TimeMap")
                    }
                    Button("Done", action: onDismiss)
                        .fontWeight(.semibold)
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
