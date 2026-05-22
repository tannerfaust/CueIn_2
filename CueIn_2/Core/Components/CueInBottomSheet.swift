import SwiftUI

// MARK: - CueInBottomSheet dismiss style

enum CueInBottomSheetDismissStyle: Equatable {
    /// Trailing “Done” (default for settings-style sheets).
    case doneTrailing
    /// Leading circular close control (modal-style).
    case closeLeading
}

// MARK: - CueInBottomSheet
/// Settings-style sheet shell: matches task / block editors — `NavigationStack`, blurred bar, scroll on app background.

private struct CueInBottomSheetScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct CueInBottomSheet<Content: View>: View {
    let title: String
    let onDismiss: () -> Void
    /// When set, the sheet uses ``CueInEditorToolbar`` (glass close + save) like task / block editors.
    /// Close runs this **before** ``onDismiss`` so you can roll back draft values; Save runs ``onDismiss`` only.
    var onEditorDiscard: (() -> Void)? = nil
    var editorPrincipalIcon: String? = "gearshape.fill"
    var editorSaveForeground: Color = CueInColors.accentFocus
    var floatingAccessory: AnyView? = nil
    var floatingAccessoryThreshold: CGFloat = 170
    /// Trailing “Done” vs leading close control.
    var toolbarDismissStyle: CueInBottomSheetDismissStyle = .doneTrailing
    @ViewBuilder var content: () -> Content

    @State private var scrollOffset: CGFloat = 0

    private var showsFloatingAccessory: Bool {
        floatingAccessory != nil && scrollOffset > floatingAccessoryThreshold
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CueInColors.background.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: CueInBottomSheetScrollOffsetPreferenceKey.self,
                            value: -proxy.frame(in: .named("CueInBottomSheetScroll")).minY
                        )
                    }
                    .frame(height: 0)

                    content()
                        .padding(.horizontal, CueInSpacing.screenHorizontal)
                        .padding(.top, CueInSpacing.sm)
                        .padding(.bottom, CueInSpacing.xxl)
                }
                .coordinateSpace(name: "CueInBottomSheetScroll")
                .scrollDismissesKeyboard(.interactively)
                .onPreferenceChange(CueInBottomSheetScrollOffsetPreferenceKey.self) { value in
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        scrollOffset = value
                    }
                }

                if let floatingAccessory, showsFloatingAccessory {
                    VStack {
                        floatingAccessory
                            .padding(.horizontal, CueInSpacing.screenHorizontal)
                            .padding(.top, CueInSpacing.xs)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
                    .allowsHitTesting(false)
                }
            }
            .navigationTitle(onEditorDiscard == nil ? title : "")
            .cueInNavigationBarTitleDisplayMode(.inline)
            .cueInNavigationToolbarChrome(isVisible: onEditorDiscard == nil)
            .toolbar {
                if let onEditorDiscard {
                    CueInEditorToolbar(
                        saveEnabled: true,
                        onClose: {
                            onEditorDiscard()
                            onDismiss()
                        },
                        onSave: onDismiss,
                        saveForeground: editorSaveForeground,
                        saveButtonStyle: editorPrincipalIcon == nil ? .plainIcon : .blueCircle
                    ) {
                        if let editorPrincipalIcon {
                            CueInEditorPrincipalChip(
                                icon: editorPrincipalIcon,
                                title: title,
                                tint: CueInColors.textSecondary
                            )
                        } else {
                            CueInEditorPrincipalText(title: title)
                        }
                    }
                } else {
                    switch toolbarDismissStyle {
                    case .doneTrailing:
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done", action: onDismiss)
                                .font(CueInTypography.bodyMedium)
                                .foregroundStyle(CueInColors.accentFocus)
                        }
                    case .closeLeading:
                        ToolbarItem(placement: .cancellationAction) {
                            Button(action: onDismiss) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(CueInColors.textPrimary.opacity(0.55))
                                    .frame(width: 30, height: 30)
                                    .background(
                                        Circle().fill(CueInColors.surfaceTertiary.opacity(0.95))
                                    )
                                    .overlay(
                                        Circle()
                                            .strokeBorder(CueInColors.cardBorder.opacity(0.45), lineWidth: 0.5)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Close")
                        }
                    }
                }
            }
        }
        .cueInPreferredColorScheme()
    }
}

// MARK: - Sheet Action Row — neutral by default

struct SheetActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var tint: Color = CueInColors.textSecondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: CueInSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(tint == CueInColors.textSecondary ? CueInColors.textPrimary : tint)
                    .frame(width: 36, height: 36)
                    .background(CueInColors.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)

                    Text(subtitle)
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CueInColors.textTertiary)
            }
            .padding(.vertical, CueInSpacing.sm)
        }
    }
}
