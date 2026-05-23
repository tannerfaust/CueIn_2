import SwiftUI

#if os(iOS)

// MARK: - ShellFabOverflowMenu
/// Long-press FAB overflow: same liquid-glass approach as ``ScheduleBlockContextMenu``
/// (native `glassEffect` + `GlassEffectContainer` on iOS 26). Does **not** participate in
/// parent layout width/height beyond its own intrinsic frame.

struct ShellFabOverflowMenu: View {
    struct Row: Identifiable {
        let id: String
        let icon: String
        let title: String
        let subtitle: String
        let tint: Color?
        let isEnabled: Bool
        let action: () -> Void

        init(
            icon: String,
            title: String,
            subtitle: String,
            tint: Color? = nil,
            isEnabled: Bool = true,
            action: @escaping () -> Void
        ) {
            self.id = "\(icon)|\(title)"
            self.icon = icon
            self.title = title
            self.subtitle = subtitle
            self.tint = tint
            self.isEnabled = isEnabled
            self.action = action
        }
    }

    let rows: [Row]
    var style: Style = .standard

    enum Style {
        case standard
        case execution

        var width: CGFloat {
            switch self {
            case .standard: return 236
            case .execution: return 224
            }
        }

        var rowMinHeight: CGFloat {
            switch self {
            case .standard: return 42
            case .execution: return 40
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .standard: return 22
            case .execution: return 20
            }
        }

        var tint: Color {
            switch self {
            case .standard: return Color.white.opacity(0.16)
            case .execution: return Color(red: 1.0, green: 0.86, blue: 0.35).opacity(0.15)
            }
        }
    }

    var body: some View {
        menuSurface
            .shadow(color: Color.black.opacity(0.30), radius: 22, y: 14)
            .transition(
                .asymmetric(
                    insertion: .opacity
                        .combined(with: .move(edge: .bottom))
                        .combined(with: .scale(scale: 0.94, anchor: .bottomTrailing)),
                    removal: .opacity
                        .combined(with: .scale(scale: 0.97, anchor: .bottomTrailing))
                )
            )
    }

    @ViewBuilder
    private var menuSurface: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 6) {
                menuBody
                    .shellFabMenuGlassChrome(style: style)
            }
        } else {
            menuBody
                .shellFabMenuGlassChrome(style: style)
        }
    }

    /// Full list, no scrolling — every action stays visible at once.
    private var menuBody: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(rows) { row in
                menuRow(row)
            }
        }
        .padding(7)
        .frame(width: style.width, alignment: .leading)
    }

    @ViewBuilder
    private func menuRow(_ row: Row) -> some View {
        Button(action: row.action) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: row.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(row.tint ?? CueInColors.textPrimary)
                    .frame(width: 22, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(CueInTypography.captionMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                        .multilineTextAlignment(.leading)

                    Text(row.subtitle)
                        .font(CueInTypography.micro)
                        .foregroundStyle(CueInColors.textTertiary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: style.rowMinHeight, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.045))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!row.isEnabled)
        .opacity(row.isEnabled ? 1 : 0.42)
    }
}

// MARK: - Chrome (matches Schedule block context menu)

private struct ShellFabMenuGlassChrome: ViewModifier {
    let style: ShellFabOverflowMenu.Style

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
                .glassEffect(
                    .regular.tint(style.tint).interactive(),
                    in: RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                )
        } else {
            content
                .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7)
                }
        }
    }
}

private extension View {
    func shellFabMenuGlassChrome(style: ShellFabOverflowMenu.Style) -> some View {
        modifier(ShellFabMenuGlassChrome(style: style))
    }
}

#endif
