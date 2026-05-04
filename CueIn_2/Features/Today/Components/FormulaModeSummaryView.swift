import SwiftUI

// MARK: - FormulaModeSummaryView
/// Compact identity card for the active Today formula mode.

struct FormulaModeSummaryView: View {
    let formula: DayFormulaTemplate
    let onChangeFormula: () -> Void

    var body: some View {
        CueInCard(surface: CueInColors.surfacePrimary, padding: CueInSpacing.md) {
            VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                HStack(alignment: .top, spacing: CueInSpacing.md) {
                    Image(systemName: formula.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(CueInColors.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(CueInColors.surfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("FORMULA")
                            .font(CueInTypography.micro)
                            .foregroundStyle(CueInColors.textTertiary)
                            .tracking(0.5)

                        Text(formula.name)
                            .font(CueInTypography.headline)
                            .foregroundStyle(CueInColors.textPrimary)

                        Text(formula.summary)
                            .font(CueInTypography.caption)
                            .foregroundStyle(CueInColors.textSecondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)

                    Button(action: onChangeFormula) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CueInColors.textPrimary)
                            .frame(width: 30, height: 30)
                            .background(CueInColors.surfaceSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Change formula")
                }

                HStack(spacing: CueInSpacing.sm) {
                    metric(text: formula.targetDurationLabel)
                    metric(text: "\(formula.blockCount) blocks")
                    metric(text: "\(formula.totalTaskCount) tasks")
                }

                if let rule = formula.rules.first {
                    Text(rule)
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
    }

    private func metric(text: String) -> some View {
        Text(text)
            .font(CueInTypography.micro)
            .foregroundStyle(CueInColors.textSecondary)
            .padding(.horizontal, CueInSpacing.sm)
            .padding(.vertical, 6)
            .background(CueInColors.surfaceSecondary)
            .clipShape(Capsule())
    }
}
