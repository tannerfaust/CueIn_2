import SwiftUI

// MARK: - FocusSoundscapeInlineControl

/// In-card Sounds control for focus mode: compact module icon → mini player after a preset is chosen.
struct FocusSoundscapeInlineControl: View {
    @Bindable var store: FocusSoundscapeStore
    var accent: Color = CueInColors.accentRoutine
    let onOpenSounds: () -> Void

    private var showsPlayer: Bool {
        store.preset != .off
    }

    var body: some View {
        Group {
            if showsPlayer {
                miniPlayer
            } else {
                chooseSoundButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(response: 0.38, dampingFraction: 0.84), value: showsPlayer)
        .animation(.easeInOut(duration: 0.22), value: store.isPlaying)
    }

    // MARK: - Collapsed

    private var chooseSoundButton: some View {
        Button(action: onOpenSounds) {
            ZStack {
                FocusSoundscapeGlassCircle(accent: accent)
                Image(systemName: FocusSoundscapePreset.moduleSystemImage)
                    .font(.system(size: 18, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(accent)
            }
            .frame(width: 40, height: 40)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sounds")
        .accessibilityHint("Choose focus sound")
    }

    // MARK: - Expanded player

    private var miniPlayer: some View {
        HStack(spacing: CueInSpacing.sm) {
            playPauseButton

            FocusSoundscapeWaveformMeter(
                isAnimating: store.isPlaying,
                accent: accent
            )

            Button(action: onOpenSounds) {
                Text(store.preset.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(CueInColors.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(store.preset.title), change sound")
        }
        .padding(.leading, 6)
        .padding(.trailing, CueInSpacing.md)
        .padding(.vertical, 7)
        .background {
            FocusSoundscapeGlassCapsule(
                accent: accent,
                isActive: store.isPlaying
            )
        }
    }

    private var playPauseButton: some View {
        Button {
            store.togglePlayback()
        } label: {
            Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(CueInColors.textPrimary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(accent.opacity(store.isPlaying ? 0.34 : 0.22))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.isPlaying ? "Pause sound" : "Play sound")
    }
}

// MARK: - Waveform meter

private struct FocusSoundscapeWaveformMeter: View {
    let isAnimating: Bool
    let accent: Color

    private let barCount = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 28.0, paused: !isAnimating)) { timeline in
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(accent.opacity(isAnimating ? 0.92 : 0.45))
                        .frame(width: 2.5, height: barHeight(index: index, date: timeline.date))
                }
            }
            .frame(width: 18, height: 16, alignment: .center)
        }
        .accessibilityHidden(true)
    }

    private func barHeight(index: Int, date: Date) -> CGFloat {
        guard isAnimating else { return 5 }
        let phase = date.timeIntervalSinceReferenceDate * 5.2 + Double(index) * 0.85
        return 4 + CGFloat((sin(phase) + 1) * 0.5) * 9
    }
}

// MARK: - Liquid glass chrome

private struct FocusSoundscapeGlassCircle: View {
    let accent: Color

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            Circle()
                .fill(Color.clear)
                .frame(width: 40, height: 40)
                .glassEffect(
                    .regular.tint(accent.opacity(0.12)).interactive(),
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                }
        } else {
            Circle()
                .fill(CueInColors.surfacePrimary.opacity(0.42))
                .overlay {
                    Circle()
                        .strokeBorder(accent.opacity(0.2), lineWidth: 0.5)
                }
        }
    }
}

private struct FocusSoundscapeGlassCapsule: View {
    let accent: Color
    let isActive: Bool

    var body: some View {
        let shape = Capsule(style: .continuous)
        if #available(iOS 26.0, macOS 26.0, *) {
            shape
                .fill(Color.clear)
                .glassEffect(
                    .regular
                        .tint(accent.opacity(isActive ? 0.18 : 0.10))
                        .interactive(),
                    in: shape
                )
                .overlay {
                    shape.strokeBorder(
                        accent.opacity(isActive ? 0.32 : 0.16),
                        lineWidth: 0.65
                    )
                }
        } else {
            shape
                .fill(CueInColors.surfacePrimary.opacity(isActive ? 0.48 : 0.36))
                .overlay {
                    shape.strokeBorder(accent.opacity(0.22), lineWidth: 0.5)
                }
        }
    }
}

// MARK: - FocusSoundscapeToolbarButton

/// Minimal toolbar opener (legacy wrapper only).
struct FocusSoundscapeToolbarButton: View {
    @Bindable var store: FocusSoundscapeStore
    var accent: Color = CueInColors.accentRoutine
    let onOpenSounds: () -> Void

    var body: some View {
        Button(action: onOpenSounds) {
            Image(systemName: FocusSoundscapePreset.moduleSystemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(CueInColors.textPrimary)
        }
        .accessibilityLabel("Sounds")
    }
}

typealias FocusSoundscapeNowPlayingStrip = FocusSoundscapeInlineControl
