#if canImport(AVFoundation) && os(iOS)
import AVFoundation

/// Result tones of the reflex mode (specs/05 "Sonuç sesi"): short, no speech.
/// Synthesized sine tones; the audio session is SpeechOut's (specs/02 "Ses oturumu").
@MainActor public final class ToneOut {
    public enum Tone: Sendable { case correct, wrong, doubleWrong }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    public var enabled = true

    public init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    public func play(_ tone: Tone) {
        guard enabled else { return }
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }
        switch tone {
        case .correct: schedule([(1320, 0.06)])
        case .wrong: schedule([(330, 0.12)])
        case .doubleWrong: schedule([(330, 0.1), (0, 0.06), (330, 0.1)])
        }
        player.play()
    }

    public func stop() {
        player.stop()
        engine.stop()
    }

    /// (frequency Hz, seconds); frequency 0 is silence. A 5 ms ramp avoids clicks.
    private func schedule(_ parts: [(Double, Double)]) {
        let rate = format.sampleRate
        let total = AVAudioFrameCount(parts.map { $0.1 * rate }.reduce(0, +))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: total), let data = buffer.floatChannelData?[0] else { return }
        var i = 0
        for (freq, seconds) in parts {
            let n = Int(seconds * rate)
            let ramp = Int(0.005 * rate)
            for k in 0..<n {
                let env = Swift.min(1, Double(k) / Double(ramp), Double(n - k) / Double(ramp))
                data[i] = freq == 0 ? 0 : Float(0.4 * env * sin(2 * .pi * freq * Double(k) / rate))
                i += 1
            }
        }
        buffer.frameLength = AVAudioFrameCount(i)
        player.scheduleBuffer(buffer, completionHandler: nil)
    }
}
#endif
