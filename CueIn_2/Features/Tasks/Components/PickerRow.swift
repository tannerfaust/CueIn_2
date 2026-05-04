import SwiftUI

// MARK: - PickerRow
/// Reusable "label on the left, value on the right, tap to change" row
/// used across the detail + create sheets. The trailing closure hosts
/// whatever control opens when tapped (Menu, DatePicker, sheet, etc.).

struct PickerRow<Trailing: View>: View {
    let icon: String
    let label: String
    var iconColor: Color = CueInColors.textSecondary
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: CueInSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 18)

            Text(label)
                .font(CueInTypography.body)
                .foregroundStyle(CueInColors.textSecondary)

            Spacer()

            trailing()
        }
        .padding(.horizontal, CueInSpacing.base)
        .padding(.vertical, 12)
    }
}

// MARK: - Section container

struct SheetSection<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content

    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            if let title {
                Text(title.uppercased())
                    .font(Font.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(CueInColors.textTertiary)
                    .padding(.horizontal, CueInSpacing.screenHorizontal)
            }
            VStack(spacing: 0) {
                content()
            }
            .background(CueInColors.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous)
                    .strokeBorder(CueInColors.cardBorder, lineWidth: 0.5)
            )
            .padding(.horizontal, CueInSpacing.screenHorizontal)
        }
    }
}

// MARK: - SheetRowDivider

struct SheetRowDivider: View {
    var body: some View {
        Divider()
            .background(CueInColors.divider)
            .padding(.leading, CueInSpacing.base + 18 + CueInSpacing.md)
    }
}
