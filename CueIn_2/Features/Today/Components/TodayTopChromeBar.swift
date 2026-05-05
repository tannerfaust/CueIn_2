import SwiftUI

// MARK: - Today chrome title sizing

private enum TodayChromeTitleFont {
    /// Between ``CueInTypography/title`` (22pt) and ``CueInTypography/largeTitle`` (28pt).
    static let prominent = Font.system(size: 26, weight: .semibold, design: .default)
}

// MARK: - TodayTopChromeBar
/// Top row for Today: title ownership plus compact glass controls.

struct TodayTopChromeBar<ScheduleMenu: View, BeforeTrailing: View, Trailing: View>: View {
    var title: String = "Today"
    /// Slightly larger nav-style title (e.g. To-do mode).
    var prominentTitle: Bool = false
    let showsStart: Bool
    let onStart: () -> Void
    let showsSchedulePlayback: Bool
    let schedulePlaybackSystemImage: String
    let schedulePlaybackAccessibilityLabel: String
    let onSchedulePlayback: () -> Void
    /// Jiggle (home-screen) rearrange — exit on Done.
    var showsRearrangeDone: Bool = false
    var onRearrangeDone: () -> Void = {}
    @ViewBuilder var scheduleLiveMenu: () -> ScheduleMenu
    /// Shown immediately left of the trailing menu (e.g. To-do summary pill).
    @ViewBuilder var beforeTrailing: () -> BeforeTrailing
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: CueInSpacing.sm) {
            Text(title)
                .font(prominentTitle ? TodayChromeTitleFont.prominent : CueInTypography.title)
                .foregroundStyle(CueInColors.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if showsRearrangeDone {
                TodayChromeCapsuleButton(title: "Done", action: onRearrangeDone)
            }

            if showsStart {
                TodayChromeCapsuleButton(title: "Start", action: onStart)
            }

            if showsSchedulePlayback {
                TodayChromeIconButton(
                    systemImage: schedulePlaybackSystemImage,
                    accessibilityLabel: schedulePlaybackAccessibilityLabel,
                    action: onSchedulePlayback
                )
            }

            scheduleLiveMenu()

            beforeTrailing()

            trailing()
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
        .padding(.top, CueInLayout.topChromeContentTopPadding)
        .padding(.bottom, CueInLayout.topChromeContentBottomPadding)
        .dynamicTypeSize(.xSmall ... .large)
    }
}

// MARK: - Start (capsule, bigger)

struct TodayChromeCapsuleButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(CueInTypography.captionMedium)
                .foregroundStyle(CueInColors.textPrimary)
                .padding(.horizontal, 16)
                .frame(height: CueInLayout.topChromeButtonHeight)
                .contentShape(Capsule(style: .continuous))
                .cueInGlass(.capsule)
        }
        .buttonStyle(.plain)
    }
}

struct TodayChromeIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CueInColors.textPrimary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .cueInGlass(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - ⋯ (bigger circle)

struct TodayChromeMenuGlyph: View {
    var body: some View {
        CueInOverflowMenuGlyph()
    }
}

// MARK: - Shared glass modifiers (use unified CueInGlassModifier)

struct TodayCapsuleGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.cueInGlass(.capsule)
    }
}

struct TodayCircleGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.cueInGlass(.circle)
    }
}
