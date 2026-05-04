import SwiftUI

// MARK: - CueInChip
/// Lightweight pill/tag. Neutral by default — only tinted when semantic.

struct CueInChip: View {
    let label: String
    var icon: String? = nil
    var tint: Color = CueInColors.textSecondary
    var style: ChipStyle = .subtle

    enum ChipStyle {
        case subtle
        case outlined
        case solid
    }

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .medium))
            }
            Text(label)
                .font(CueInTypography.micro)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(foregroundColor)
        .background(backgroundFill)
        .clipShape(Capsule())
        .overlay(borderOverlay)
    }

    private var foregroundColor: Color {
        switch style {
        case .subtle:   return tint
        case .outlined: return tint
        case .solid:    return .white
        }
    }

    private var backgroundFill: some ShapeStyle {
        switch style {
        case .subtle:   return AnyShapeStyle(tint.opacity(0.12))
        case .outlined: return AnyShapeStyle(Color.clear)
        case .solid:    return AnyShapeStyle(tint)
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        if style == .outlined {
            Capsule()
                .strokeBorder(tint.opacity(0.3), lineWidth: 0.5)
        }
    }
}
