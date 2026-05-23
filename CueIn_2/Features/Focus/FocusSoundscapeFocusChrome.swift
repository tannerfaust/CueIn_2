import SwiftUI

// MARK: - FocusSoundscapeToolbarButton

/// Prominent toolbar control that opens the full Sounds sheet (not a compact menu).
struct FocusSoundscapeToolbarButton: View {
    @Bindable var store: FocusSoundscapeStore
    var accent: Color = CueInColors.accentRoutine
    let onOpenSounds: () -> Void

    private var isSoundActive: Bool {
        store.isPlaying || store.preset != .off
    }

    var body: some View {
        Button(action: onOpenSounds) {
            HStack(spacing: 6) {
                Image(systemName: toolbarIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolEffect(.variableColor.iterative, isActive: store.isPlaying && store.preset != .off)
                Text(toolbarTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 0.75)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens focus sounds")
    }

    private var toolbarIcon: String {
        if store.isPlaying, store.preset != .off {
            return store.preset.systemImage
        }
        return "waveform.circle.fill"
    }

    private var toolbarTitle: String {
        if store.isPlaying, store.preset != .off {
            return store.preset.title
        }
        if store.preset != .off {
            return store.preset.title
        }
        return "Sounds"
    }

    private var foregroundColor: Color {
        isSoundActive ? accent : CueInColors.textPrimary
    }

    private var backgroundFill: Color {
        if store.isPlaying, store.preset != .off {
            return accent.opacity(0.24)
        }
        if store.preset != .off {
            return accent.opacity(0.14)
        }
        return CueInColors.surfaceTertiary.opacity(0.72)
    }

    private var borderColor: Color {
        isSoundActive ? accent.opacity(0.45) : CueInColors.cardBorder.opacity(0.65)
    }

    private var accessibilityLabel: String {
        if store.isPlaying, store.preset != .off {
            return "Sounds, \(store.preset.title), playing"
        }
        if store.preset != .off {
            return "Sounds, \(store.preset.title)"
        }
        return "Sounds, off"
    }
}

// MARK: - FocusSoundscapeNowPlayingStrip

/// Inline playback controls embedded in the focus time-block card.
struct FocusSoundscapeNowPlayingStrip: View {
    @Bindable var store: FocusSoundscapeStore
    var accent: Color = CueInColors.accentRoutine
    let onOpenSounds: () -> Void

    var body: some View {
        if store.preset == .off, !store.isPlaying {
            soundscapeInviteRow
        } else {
            nowPlayingRow
        }
    }

    private var soundscapeInviteRow: some View {
        Button(action: onOpenSounds) {
            HStack(spacing: CueInSpacing.sm) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Focus sounds")
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                    Text("Open sounds & ambience")
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CueInColors.textTertiary)
            }
            .padding(.horizontal, CueInSpacing.md)
            .padding(.vertical, CueInSpacing.sm + 2)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(CueInColors.surfacePrimary.opacity(0.35))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(accent.opacity(0.22), lineWidth: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open focus sounds")
    }

    private var nowPlayingRow: some View {
        HStack(spacing: CueInSpacing.sm) {
            playbackToggleButton

            Button(action: onOpenSounds) {
                HStack(spacing: CueInSpacing.sm) {
                    Image(systemName: store.preset.systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(accent.opacity(store.isPlaying ? 0.22 : 0.12))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.preset == .off ? "Soundscape" : store.preset.title)
                            .font(CueInTypography.bodyMedium)
                            .foregroundStyle(CueInColors.textPrimary)
                            .lineLimit(1)
                        Text(playbackStatus)
                            .font(CueInTypography.caption)
                            .foregroundStyle(store.isPlaying ? accent : CueInColors.textTertiary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CueInColors.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change sound, opens sounds panel")

            stopButton
        }
        .padding(.horizontal, CueInSpacing.md)
        .padding(.vertical, CueInSpacing.sm + 2)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CueInColors.surfacePrimary.opacity(store.isPlaying ? 0.42 : 0.32))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(accent.opacity(store.isPlaying ? 0.38 : 0.2), lineWidth: 0.75)
        }
        .animation(.easeInOut(duration: 0.2), value: store.isPlaying)
        .animation(.easeInOut(duration: 0.2), value: store.preset)
    }

    private var playbackToggleButton: some View {
        Button {
            if store.preset == .off {
                onOpenSounds()
            } else {
                store.togglePlayback()
            }
        } label: {
            Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(CueInColors.textPrimary)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(accent.opacity(0.28))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.isPlaying ? "Pause sound" : "Play sound")
    }

    private var stopButton: some View {
        Button {
            store.stopPlayback()
        } label: {
            Image(systemName: "stop.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(CueInColors.textSecondary)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(CueInColors.surfaceTertiary.opacity(0.85))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop sound")
        .disabled(!store.isPlaying && store.preset == .off)
        .opacity(store.isPlaying || store.preset != .off ? 1 : 0.4)
    }

    private var playbackStatus: String {
        if store.preset == .off { return "Tap to choose a sound" }
        return store.isPlaying ? "Playing" : "Paused"
    }
}
