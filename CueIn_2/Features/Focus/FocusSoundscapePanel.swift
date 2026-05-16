import SwiftUI

// MARK: - FocusSoundscapePanel

struct FocusSoundscapePanel: View {
    @Bindable private var store = FocusSoundscapeStore.shared
    @State private var volumeSlider: Double = 0.35

    private let presetColumns = [
        GridItem(.flexible(), spacing: CueInSpacing.sm),
        GridItem(.flexible(), spacing: CueInSpacing.sm),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.xl) {
            playerCard
            presetGrid
            volumeCard
        }
        .onAppear { volumeSlider = Double(store.masterVolume) }
        .onChange(of: store.masterVolume) { _, newValue in
            volumeSlider = Double(newValue)
        }
        .onDisappear {
            store.persistMasterVolumeNow(Float(volumeSlider))
        }
    }

    private var playerCard: some View {
        CueInCard(padding: CueInSpacing.xl, cornerRadius: 22) {
            VStack(spacing: CueInSpacing.xl) {
                ZStack {
                    Circle()
                        .fill(activeTint.opacity(store.isPlaying ? 0.20 : 0.10))
                        .frame(width: 154, height: 154)
                    Circle()
                        .strokeBorder(activeTint.opacity(store.isPlaying ? 0.42 : 0.18), lineWidth: 1)
                        .frame(width: 154, height: 154)
                    Image(systemName: currentPreset.systemImage)
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(store.preset == .off ? CueInColors.textTertiary : activeTint)
                }

                VStack(spacing: CueInSpacing.xs) {
                    Text(store.preset == .off ? "Choose a sound" : currentPreset.title)
                        .font(CueInTypography.title)
                        .foregroundStyle(CueInColors.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(playbackState)
                        .font(CueInTypography.captionMedium)
                        .foregroundStyle(CueInColors.textTertiary)
                }

                Button {
                    store.togglePlayback()
                } label: {
                    Label(store.isPlaying ? "Stop" : "Play", systemImage: store.isPlaying ? "stop.fill" : "play.fill")
                        .font(CueInTypography.bodyMedium)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(store.preset == .off ? CueInColors.surfaceTertiary : activeTint)
                .disabled(store.preset == .off)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
    }

    private var presetGrid: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            sectionTitle("Presets")

            LazyVGrid(columns: presetColumns, spacing: CueInSpacing.sm) {
                ForEach(FocusSoundscapePreset.pickerOrder) { preset in
                    presetButton(preset)
                }
            }
            .padding(.horizontal, CueInSpacing.screenHorizontal)
        }
    }

    private func presetButton(_ preset: FocusSoundscapePreset) -> some View {
        let selected = store.preset == preset
        return Button {
            store.selectPreset(preset)
        } label: {
            VStack(alignment: .leading, spacing: CueInSpacing.md) {
                HStack {
                    Image(systemName: preset.systemImage)
                        .font(.system(size: 18, weight: .semibold))
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.title)
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(presetShortLabel(for: preset))
                        .font(CueInTypography.micro)
                        .foregroundStyle(CueInColors.textTertiary)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(selected ? activeTint : CueInColors.textSecondary)
            .padding(CueInSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .background(selected ? activeTint.opacity(0.15) : CueInColors.surfacePrimary, in: RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous)
                    .strokeBorder(selected ? activeTint.opacity(0.50) : CueInColors.cardBorder, lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var volumeCard: some View {
        CueInCard {
            VStack(alignment: .leading, spacing: CueInSpacing.md) {
                HStack {
                    Label("Volume", systemImage: "speaker.wave.2.fill")
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                    Spacer()
                    Text("\(Int(volumeSlider * 100))%")
                        .font(CueInTypography.captionMedium)
                        .foregroundStyle(CueInColors.textTertiary)
                        .monospacedDigit()
                }

                Slider(value: Binding(
                    get: { volumeSlider },
                    set: { newValue in
                        volumeSlider = newValue
                        let v = Float(newValue)
                        store.applyAudibleMasterVolume(v)
                        store.scheduleMasterVolumePersist(v)
                    }
                ), in: 0...1)
                .tint(activeTint)
                .disabled(store.preset == .off && !store.isPlaying)
            }
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(CueInTypography.headline)
            .foregroundStyle(CueInColors.textPrimary)
            .padding(.horizontal, CueInSpacing.screenHorizontal)
    }

    private var currentPreset: FocusSoundscapePreset {
        store.preset
    }

    private var activeTint: Color {
        CueInColors.accentRoutine
    }

    private var playbackState: String {
        if store.preset == .off { return "No audio selected" }
        return store.isPlaying ? "Playing" : "Ready"
    }

    private func presetShortLabel(for preset: FocusSoundscapePreset) -> String {
        switch preset {
        case .off: return "Silence"
        case .pinkVeil: return "Light mask"
        case .brownDepth: return "Deep mask"
        case .slowPulseVeil: return "Gentle pulse"
        case .isochronicBeta: return "Rhythmic"
        case .binauralBetaHeadphones: return "Headphones"
        }
    }
}

#Preview {
    ZStack {
        CueInColors.background.ignoresSafeArea()
        ScrollView {
            FocusSoundscapePanel()
                .padding(.vertical, CueInSpacing.lg)
        }
    }
    .cueInPreferredColorScheme()
}
