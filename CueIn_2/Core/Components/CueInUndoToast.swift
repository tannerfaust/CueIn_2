import SwiftUI

// MARK: - CueInUndoToast
/// Shared undo-capable feedback toast for reversible app actions.

struct CueInUndoToast: View {
    let icon: String
    let title: String
    let message: String
    let tint: Color
    let undoTitle: String
    let style: CueInToastStyle
    let actions: [CueInToastActionModel]
    let onUndo: @MainActor () -> Void
    let onDismiss: @MainActor () -> Void

    @State private var dragOffset: CGFloat = 0

    private var isWarning: Bool {
        if case .warning = style { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isWarning ? CueInSpacing.sm : 0) {
            HStack(alignment: isWarning ? .top : .center, spacing: CueInSpacing.md) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(isWarning ? 0.26 : 0.18))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(CueInTypography.captionMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                        .lineLimit(isWarning ? 2 : 1)
                    Text(message)
                        .font(CueInTypography.micro)
                        .foregroundStyle(isWarning ? CueInColors.textPrimary.opacity(0.72) : CueInColors.textSecondary)
                        .lineLimit(isWarning ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: CueInSpacing.sm)

                if !isWarning {
                    toastButton(title: undoTitle, systemImage: nil, filled: false, action: onUndo)
                }
            }

            if isWarning {
                HStack(spacing: CueInSpacing.xs) {
                    ForEach(actions) { action in
                        toastButton(
                            title: action.title,
                            systemImage: action.systemImage,
                            filled: false,
                            action: action.action
                        )
                    }

                    Spacer(minLength: 0)
                    toastButton(title: undoTitle, systemImage: "xmark", filled: true, action: onUndo)
                }
            }
        }
        .padding(.leading, CueInSpacing.md)
        .padding(.trailing, isWarning ? CueInSpacing.sm : 8)
        .padding(.vertical, isWarning ? CueInSpacing.sm : 8)
        .modifier(CueInUndoToastGlassModifier(tint: tint, style: style))
        .shadow(color: tint.opacity(isWarning ? 0.28 : 0.20), radius: isWarning ? 30 : 24, x: 0, y: 12)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .offset(y: dragOffset)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    dragOffset = max(value.translation.height, 0)
                }
                .onEnded { value in
                    if value.translation.height > 42 {
                        onDismiss()
                    } else {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }

    private func toastButton(
        title: String,
        systemImage: String?,
        filled: Bool,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(title)
                    .font(CueInTypography.captionMedium)
                    .lineLimit(1)
            }
            .foregroundStyle(filled ? Color.black.opacity(0.86) : tint)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                filled ? tint : tint.opacity(isWarning ? 0.16 : 0.14),
                in: Capsule(style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct CueInUndoToastGlassModifier: ViewModifier {
    let tint: Color
    let style: CueInToastStyle

    private var isWarning: Bool {
        if case .warning = style { return true }
        return false
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content
                .clipShape(shape)
                .glassEffect(
                    .regular
                        .tint((isWarning ? tint : Color(hex: 0x3D8CFF)).opacity(isWarning ? 0.24 : 0.18))
                        .interactive(),
                    in: .rect(cornerRadius: 22)
                )
                .overlay {
                    shape
                        .strokeBorder(tint.opacity(isWarning ? 0.32 : 0.18), lineWidth: isWarning ? 1.0 : 0.7)
                }
        } else {
            content
                .clipShape(shape)
                .background(
                    (isWarning ? tint.opacity(0.18) : Color.clear),
                    in: shape
                )
                .background(.regularMaterial, in: shape)
                .overlay {
                    shape
                        .strokeBorder(tint.opacity(isWarning ? 0.34 : 0.22), lineWidth: isWarning ? 1.0 : 0.7)
                }
        }
    }
}
