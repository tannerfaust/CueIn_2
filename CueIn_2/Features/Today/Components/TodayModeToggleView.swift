import SwiftUI

// MARK: - TodayModeToggleView
/// Compact segmented control that behaves like a top-bar control, not a large content element.
/// Both segments keep the same width so the control never changes size when selection moves.

struct TodayModeToggleView: View {
    let selectedMode: DayEngineMode
    let onSelect: (DayEngineMode) -> Void

    @Namespace private var thumbNamespace

    private static let segmentWidth: CGFloat = 90
    private static let segmentHeight: CGFloat = 36

    var body: some View {
        HStack(spacing: 0) {
            ForEach(DayEngineMode.allCases) { mode in
                segment(mode)
            }
        }
        .padding(2)
        .modifier(CueInLiquidGlassToggleShellModifier())
        .fixedSize()
    }

    private func segment(_ mode: DayEngineMode) -> some View {
        let isSelected = selectedMode == mode

        return Button {
            guard !isSelected else { return }
            withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
                onSelect(mode)
            }
        } label: {
            ZStack {
                if isSelected {
                    CueInLiquidGlassToggleThumb()
                        .matchedGeometryEffect(id: "todayModeThumb", in: thumbNamespace)
                        .padding(1)
                }

                Text(mode.compactLabel)
                    .font(CueInTypography.caption)
                    .foregroundStyle(isSelected ? CueInColors.textPrimary : CueInColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(width: Self.segmentWidth, height: Self.segmentHeight)
            }
            .frame(width: Self.segmentWidth, height: Self.segmentHeight)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
