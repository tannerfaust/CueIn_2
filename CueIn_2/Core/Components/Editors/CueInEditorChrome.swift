import SwiftUI

// MARK: - CueIn Editor Chrome
/// Shared editor shell rules.
///
/// - Most editor sheets use the native `NavigationStack` toolbar with ``CueInEditorToolbar``.
/// - The sheet presentation owns the drag handle; the system navigation bar owns the top blur/glass.
/// - Do not draw a custom top gradient/material slab for editors. It flattens the iOS 26 glass.
/// - Close goes in `.cancellationAction`, save goes in `.confirmationAction`, and context/title goes in `.principal`.
/// - Scroll content owns only editor fields/properties.

enum CueInEditorSaveButtonStyle {
    case blueCircle
    case plainIcon
}

struct CueInEditorToolbar<Principal: View>: ToolbarContent {
    let saveEnabled: Bool
    let onClose: () -> Void
    let onSave: () -> Void
    var saveForeground: Color = CueInColors.accentFocus
    var saveButtonStyle: CueInEditorSaveButtonStyle = .blueCircle
    @ViewBuilder let principal: () -> Principal

    init(
        saveEnabled: Bool,
        onClose: @escaping () -> Void,
        onSave: @escaping () -> Void,
        saveForeground: Color = CueInColors.accentFocus,
        saveButtonStyle: CueInEditorSaveButtonStyle = .blueCircle,
        @ViewBuilder principal: @escaping () -> Principal
    ) {
        self.saveEnabled = saveEnabled
        self.onClose = onClose
        self.onSave = onSave
        self.saveForeground = saveForeground
        self.saveButtonStyle = saveButtonStyle
        self.principal = principal
    }

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        toolbarItems
            .cueInHideSharedToolbarGlassBackground()
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            CueInLiquidGlassToolbarIconButton(role: .close, action: onClose)
        }

        ToolbarItem(placement: .principal) {
            principal()
                .frame(maxWidth: 190)
        }

        ToolbarItem(placement: .confirmationAction) {
            switch saveButtonStyle {
            case .blueCircle:
                CueInLiquidGlassToolbarIconButton(
                    role: .save,
                    action: onSave,
                    isEnabled: saveEnabled
                )

            case .plainIcon:
                Button(action: onSave) {
                    CueInEditorPlainSaveButton(
                        isEnabled: saveEnabled,
                        foreground: saveForeground
                    )
                }
                .disabled(!saveEnabled)
                .buttonStyle(.plain)
                .accessibilityLabel("Save")
            }
        }
    }
}

private struct CueInEditorPlainSaveButton: View {
    let isEnabled: Bool
    var foreground: Color = CueInColors.accentFocus

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(isEnabled ? foreground : CueInColors.textTertiary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

struct CueInEditorPrincipalChip: View {
    let icon: String
    let title: String
    var tint: Color = CueInColors.textSecondary

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(CueInTypography.captionMedium)
                .foregroundStyle(CueInColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 13)
        .frame(height: 38)
        .cueInEditorGlassCapsule()
    }
}

struct CueInEditorPrincipalText: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(CueInColors.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
    }
}

// MARK: - Settings / inspector cards
/// Grouped panel matching ``ScheduleBlockEditorForm`` editor cards: frosted block, uppercase label, subtle rim.

struct CueInEditorSettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    private let cornerRadius: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            Text(title.uppercased())
                .font(CueInTypography.micro)
                .tracking(0.4)
                .foregroundStyle(CueInColors.textTertiary)

            content()
        }
        .padding(.horizontal, CueInSpacing.md)
        .padding(.vertical, CueInSpacing.sm + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cueInEditorGlassSurface(cornerRadius: cornerRadius)
    }
}

extension View {
    @ViewBuilder
    func cueInEditorGlassCapsule() -> some View {
        self.cueInGlass(.capsule)
    }

    @ViewBuilder
    func cueInEditorGlassSurface(cornerRadius: CGFloat) -> some View {
        self.cueInGlass(
            .roundedRect(cornerRadius: cornerRadius),
            tint: Color.white.opacity(0.08),
            showsBorder: true,
            borderColor: Color.white.opacity(0.11),
            borderWidth: 0.55
        )
    }
}
