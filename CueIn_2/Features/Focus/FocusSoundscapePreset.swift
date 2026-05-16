import Foundation

// MARK: - FocusSoundscapePreset

/// Procedural soundscapes generated in-app (no licensed music tracks). Each maps to a DSP path in ``FocusSoundscapeEngine``.
enum FocusSoundscapePreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case off
    case pinkVeil
    case brownDepth
    case slowPulseVeil
    case isochronicBeta
    case binauralBetaHeadphones

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .pinkVeil: return "Pink veil"
        case .brownDepth: return "Brown depth"
        case .slowPulseVeil: return "Slow pulse veil"
        case .isochronicBeta: return "Bright pulse (β)"
        case .binauralBetaHeadphones: return "Binaural β (headphones)"
        }
    }

    var subtitle: String {
        switch self {
        case .off: return "Silence — timer only."
        case .pinkVeil: return "Steady masking hiss; common open-office default."
        case .brownDepth: return "Deeper rumble; stronger low-frequency masking."
        case .slowPulseVeil: return "Gentle amplitude swell on pink noise (~0.12 Hz)."
        case .isochronicBeta: return "Rhythmic emphasis around ~15 Hz on a soft carrier."
        case .binauralBetaHeadphones: return "8 Hz beat between ears at ~200 Hz — needs headphones."
        }
    }

    var systemImage: String {
        switch self {
        case .off: return "speaker.slash.fill"
        case .pinkVeil: return "waveform.path"
        case .brownDepth: return "waveform"
        case .slowPulseVeil: return "lungs.fill"
        case .isochronicBeta: return "dot.radiowaves.left.and.right"
        case .binauralBetaHeadphones: return "headphones"
        }
    }

    /// Maps to the DSP path in ``FocusSoundscapeEngine``.
    var engineModeRaw: Int32 {
        switch self {
        case .off: return 0
        case .pinkVeil: return 1
        case .brownDepth: return 2
        case .slowPulseVeil: return 3
        case .isochronicBeta: return 4
        case .binauralBetaHeadphones: return 5
        }
    }

    /// Stable ordering for UI chips (off first).
    static var pickerOrder: [FocusSoundscapePreset] {
        allCases
    }
}
