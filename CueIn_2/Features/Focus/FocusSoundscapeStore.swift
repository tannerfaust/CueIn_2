import AVFoundation
import Observation

// MARK: - FocusSoundscapeStore

@MainActor
@Observable
final class FocusSoundscapeStore {
    static let shared = FocusSoundscapeStore()

    private static let keyPreset = "cuein.focus.soundscape.preset.v1"
    private static let keyVolume = "cuein.focus.soundscape.volume.v1"

    private let defaults = UserDefaults.standard
    private var engine = FocusSoundscapeEngine()

    @ObservationIgnored private var volumePersistTask: Task<Void, Never>?
    /// When the slider adjusts gain without updating ``masterVolume`` yet, this tracks the audible level for flush on preset change / tab exit.
    @ObservationIgnored private var lastInteractiveMasterVolume: Float?

    private(set) var isPlaying = false
    private(set) var preset: FocusSoundscapePreset

    /// 0…1 linear gain before the procedural mix.
    var masterVolume: Float {
        didSet {
            let clamped = max(0, min(1, masterVolume))
            if clamped != masterVolume {
                masterVolume = clamped
                return
            }
            if abs(masterVolume - oldValue) <= 1e-4 {
                return
            }
            defaults.set(masterVolume, forKey: Self.keyVolume)
            engine.setMasterVolume(masterVolume)
        }
    }

    private init() {
        let raw = defaults.string(forKey: Self.keyPreset) ?? FocusSoundscapePreset.off.rawValue
        preset = FocusSoundscapePreset(rawValue: raw) ?? .off
        let v = defaults.object(forKey: Self.keyVolume) as? Float ?? 0.35
        masterVolume = max(0, min(1, v))
        engine.setMasterVolume(masterVolume)
        engine.setMode(raw: preset.engineModeRaw)
    }

    /// Updates the audio graph immediately without touching persisted preferences or observation traffic.
    /// Use while dragging the level slider; call ``scheduleMasterVolumePersist(_:)`` or ``persistMasterVolumeNow(_:)`` to save.
    func applyAudibleMasterVolume(_ value: Float) {
        let clamped = max(0, min(1, value))
        lastInteractiveMasterVolume = clamped
        engine.setMasterVolume(clamped)
    }

    /// Writes ``masterVolume`` after the slider has been quiet briefly (avoids disk + observation churn every frame).
    func scheduleMasterVolumePersist(_ value: Float) {
        let clamped = max(0, min(1, value))
        volumePersistTask?.cancel()
        volumePersistTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            masterVolume = clamped
            lastInteractiveMasterVolume = nil
            volumePersistTask = nil
        }
    }

    /// Cancels any debounced persist and commits immediately (e.g. when leaving the Focus screen).
    func persistMasterVolumeNow(_ value: Float) {
        volumePersistTask?.cancel()
        volumePersistTask = nil
        masterVolume = max(0, min(1, value))
        lastInteractiveMasterVolume = nil
    }

    private func flushInteractiveVolumeIfNeeded() {
        volumePersistTask?.cancel()
        volumePersistTask = nil
        guard let v = lastInteractiveMasterVolume else { return }
        masterVolume = v
        lastInteractiveMasterVolume = nil
    }

    func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            guard preset != .off else { return }
            startPlayback()
        }
    }

    func selectPreset(_ newPreset: FocusSoundscapePreset) {
        flushInteractiveVolumeIfNeeded()
        guard newPreset != preset else { return }
        let wasPlaying = isPlaying
        preset = newPreset
        defaults.set(preset.rawValue, forKey: Self.keyPreset)
        engine.setMode(raw: preset.engineModeRaw)
        engine.setMasterVolume(masterVolume)

        if newPreset == .off {
            stopPlayback()
        } else if wasPlaying {
            do {
                try configureSessionIfNeeded()
                try engine.start(mode: preset.engineModeRaw, volume: masterVolume)
            } catch {
                stopPlayback()
            }
        }
    }

    func startPlayback() {
        guard preset != .off else { return }
        do {
            try configureSessionIfNeeded()
            try engine.start(mode: preset.engineModeRaw, volume: masterVolume)
            isPlaying = true
        } catch {
            isPlaying = false
        }
    }

    func stopPlayback() {
        engine.stop()
        isPlaying = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func resetForFreshInstall() {
        volumePersistTask?.cancel()
        volumePersistTask = nil
        lastInteractiveMasterVolume = nil
        stopPlayback()
        engine.removeGraphIfInstalled()
        engine = FocusSoundscapeEngine()
        preset = .off
        masterVolume = 0.35
        defaults.removeObject(forKey: Self.keyPreset)
        defaults.removeObject(forKey: Self.keyVolume)
        engine.setMode(raw: preset.engineModeRaw)
        engine.setMasterVolume(masterVolume)
    }

    private func configureSessionIfNeeded() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true, options: [])
    }
}
