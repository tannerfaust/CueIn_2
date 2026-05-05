import SwiftUI

// MARK: - ScheduleBlockContextMenu
/// Floating Schedule command cluster. It overlays the stack instead of pushing blocks down.

struct ScheduleBlockContextMenu: View {
    let onEdit: () -> Void
    let onAddTask: () -> Void
    let onRearrange: () -> Void
    /// Jiggle is already on — hidden row; use Done in the top bar to exit.
    var isJiggleRearrangeActive: Bool = false
    var canRearrange: Bool = true
    let onDelete: () -> Void
    let canDelete: Bool

    var body: some View {
        menuSurface
        .transition(.asymmetric(
            insertion: .opacity
                .combined(with: .move(edge: .top))
                .combined(with: .scale(scale: 0.92, anchor: .topTrailing)),
            removal: .opacity
                .combined(with: .scale(scale: 0.96, anchor: .topTrailing))
        ))
    }

    @ViewBuilder
    private var menuSurface: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 7) {
                menuContent
                    .menuGlassBackground(interactive: true)
            }
        } else {
            menuContent
                .menuGlassBackground(interactive: true)
        }
    }

    private var menuContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            menuButton(title: "Edit", systemImage: "pencil", role: nil, action: onEdit)
            menuButton(title: "Add task", systemImage: "plus", role: nil, action: onAddTask)
            if !isJiggleRearrangeActive {
                menuButton(
                    title: "Rearrange",
                    systemImage: "arrow.up.arrow.down",
                    role: nil,
                    action: onRearrange
                )
                .disabled(!canRearrange)
                .opacity(canRearrange ? 1 : 0.42)
            }
            menuButton(
                title: "Delete",
                systemImage: "trash",
                role: canDelete ? .destructive : nil,
                action: onDelete
            )
            .disabled(!canDelete)
            .opacity(canDelete ? 1 : 0.42)
        }
        .padding(7)
        .frame(width: 188, alignment: .leading)
        .shadow(color: Color.black.opacity(0.30), radius: 22, y: 14)
    }

    @ViewBuilder
    private func menuButton(
        title: String,
        systemImage: String,
        role: ButtonRole?,
        action: @escaping () -> Void
    ) -> some View {
        let isDestructive = role == .destructive
        let label = HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 18)
                .foregroundStyle(isDestructive ? CueInColors.danger : CueInColors.textPrimary)

            Text(title)
                .font(CueInTypography.captionMedium)
                .foregroundStyle(isDestructive ? CueInColors.danger : CueInColors.textPrimary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

        if let role {
            Button(role: role, action: action) { label }
                .buttonStyle(.plain)
        } else {
            Button(action: action) { label }
                .buttonStyle(.plain)
        }
    }
}

// MARK: - Liquid/glass background

private struct MenuGlassBackground: ViewModifier {
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .glassEffect(
                    interactive
                        ? .regular.tint(Color.white.opacity(0.16)).interactive()
                        : .regular.tint(Color.white.opacity(0.16)),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
        } else {
            content
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7)
                }
        }
    }
}

extension View {
    fileprivate func menuGlassBackground(interactive: Bool) -> some View {
        modifier(MenuGlassBackground(interactive: interactive))
    }
}

// MARK: - Sheets (add task)

struct AddTaskToBlockSheet: View {
    @State private var text: String = ""
    let onAdd: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        CueInBottomSheet(title: "Add a task", onDismiss: onCancel) {
            VStack(alignment: .leading, spacing: CueInSpacing.md) {
                TextField("Task name", text: $text)
                    .font(CueInTypography.bodyMedium)
                    .textInputAutocapitalization(.sentences)
                    .padding(CueInSpacing.md)
                    .background(CueInColors.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
                    .foregroundStyle(CueInColors.textPrimary)

                Button("Add") {
                    onAdd(text)
                }
                .font(CueInTypography.bodyMedium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, CueInSpacing.md)
                .foregroundStyle(SwiftUI.Color.white)
                .background(
                    CueInColors.textPrimary,
                    in: RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous)
                )
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            }
        }
    }
}
