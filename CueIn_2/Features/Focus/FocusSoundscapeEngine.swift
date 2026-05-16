import AVFoundation
import Foundation

// MARK: - FocusSoundscapeEngine

/// Real-time procedural audio. Call ``start(mode:volume:)`` / ``stop()`` from the main thread only.
final class FocusSoundscapeEngine: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?

    private var globalSample: Int64 = 0
    private var pinkB0: Float = 0
    private var pinkB1: Float = 0
    private var pinkB2: Float = 0
    private var pinkB3: Float = 0
    private var pinkB4: Float = 0
    private var pinkB5: Float = 0
    private var pinkB6: Float = 0
    private var brownState: Float = 0
    private var rngState: UInt64 = 0xDEADBEEFCAFEBABE

    private var mode: Int32 = 0
    private var masterVolume: Float = 0.35

    func setMode(raw: Int32) {
        mode = raw
    }

    func setMasterVolume(_ v: Float) {
        masterVolume = max(0, min(1, v))
    }

    func start(mode: Int32, volume: Float) throws {
        setMode(raw: mode)
        setMasterVolume(volume)

        if sourceNode == nil {
            let format = engine.outputNode.outputFormat(forBus: 0)
            let sampleRate = Float(format.sampleRate)

            let node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
                guard let self else { return noErr }
                let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
                guard abl.count >= 2,
                      let lBase = abl[0].mData?.assumingMemoryBound(to: Float.self),
                      let rBase = abl[1].mData?.assumingMemoryBound(to: Float.self)
                else { return noErr }

                let m = self.mode
                let vol = self.masterVolume
                let frames = Int(frameCount)

                for i in 0..<frames {
                    let t = Double(self.globalSample) / Double(sampleRate)
                    self.globalSample += 1

                    let white = self.nextWhiteNoise()
                    let pink = self.nextPink(from: white)
                    let brown = self.nextBrown(from: white)

                    var l: Float = 0
                    var r: Float = 0

                    switch m {
                    case 0:
                        l = 0
                        r = 0
                    case 1:
                        l = pink
                        r = pink
                    case 2:
                        l = brown
                        r = brown
                    case 3:
                        let swell = 0.45 + 0.55 * Float(0.5 * (1.0 + sin(2.0 * Double.pi * 0.12 * t)))
                        let s = pink * swell
                        l = s
                        r = s
                    case 4:
                        let carrierHz: Float = 220
                        let pulseHz: Float = 15
                        let carrier = sin(2 * Float.pi * carrierHz * Float(t))
                        let window = pow(abs(sin(2 * Float.pi * pulseHz * Float(t))), 2.2)
                        let s = carrier * window * 0.35 + pink * 0.08
                        l = s
                        r = s
                    case 5:
                        let fL: Float = 200
                        let beat: Float = 8
                        let fR = fL + beat
                        l = sin(2 * Float.pi * fL * Float(t)) * 0.45
                        r = sin(2 * Float.pi * fR * Float(t)) * 0.45
                    default:
                        l = pink
                        r = pink
                    }

                    l *= vol
                    r *= vol
                    lBase[i] = l
                    rBase[i] = r
                }
                return noErr
            }

            sourceNode = node
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            engine.prepare()
        }

        try engine.start()
    }

    func stop() {
        engine.stop()
        globalSample = 0
        pinkB0 = 0; pinkB1 = 0; pinkB2 = 0; pinkB3 = 0; pinkB4 = 0; pinkB5 = 0; pinkB6 = 0
        brownState = 0
    }

    func removeGraphIfInstalled() {
        stop()
        guard let node = sourceNode else { return }
        engine.disconnectNodeOutput(node, bus: 0)
        engine.detach(node)
        sourceNode = nil
    }

    private func nextWhiteNoise() -> Float {
        rngState &*= 6364136223846793005
        rngState &+= 1
        let u = Float(rngState & 0xFFFFFF) / Float(0xFFFFFF)
        return u * 2 - 1
    }

    private func nextPink(from white: Float) -> Float {
        pinkB0 = 0.99886 * pinkB0 + white * 0.0555179
        pinkB1 = 0.99332 * pinkB1 + white * 0.0750759
        pinkB2 = 0.96900 * pinkB2 + white * 0.1538520
        pinkB3 = 0.86650 * pinkB3 + white * 0.3104856
        pinkB4 = 0.55000 * pinkB4 + white * 0.5329522
        pinkB5 = -0.7616 * pinkB5 - white * 0.0168980
        let pink = pinkB0 + pinkB1 + pinkB2 + pinkB3 + pinkB4 + pinkB5 + pinkB6 + white * 0.5362
        pinkB6 = white * 0.115926
        return pink * 0.11
    }

    private func nextBrown(from white: Float) -> Float {
        brownState = brownState * 0.985 + white * 0.08
        return max(-1, min(1, brownState * 2.2))
    }
}
