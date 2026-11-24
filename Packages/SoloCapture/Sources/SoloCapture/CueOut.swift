import Foundation

/// `audio/<lang>/cues.json` (specs/05 "Ses dosyaları ve meta veri").
public struct CueManifest: Sendable, Equatable {
    public struct Cue: Sendable, Equatable {
        public var file: String
        /// Silence at the start of the file, ms.
        public var cueOnsetMs: Double

        public init(file: String, cueOnsetMs: Double) {
            self.file = file
            self.cueOnsetMs = cueOnsetMs
        }
    }

    public var cues: [String: Cue]

    public enum ParseError: Error, Equatable { case format(String) }

    public static func parse(_ data: Data) throws -> CueManifest {
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ParseError.format("not an object") }
        guard Set(o.keys) == ["formatVersion", "cues"], o["formatVersion"] as? Int == 1 else { throw ParseError.format("formatVersion 1 and cues") }
        guard let cues = o["cues"] as? [String: Any] else { throw ParseError.format("cues") }
        var out: [String: Cue] = [:]
        for (key, v) in cues {
            guard let c = v as? [String: Any], Set(c.keys) == ["file", "cueOnsetMs"], let file = c["file"] as? String, !file.isEmpty,
                  !file.contains("/"), let onset = (c["cueOnsetMs"] as? NSNumber)?.doubleValue, onset >= 0, onset < 1000
            else { throw ParseError.format("cues.\(key)") }
            out[key] = Cue(file: file, cueOnsetMs: onset)
        }
        return CueManifest(cues: out)
    }
}

/// When a scheduled cue is heard (specs/05 "İşaret anı"): `t_cue = planned + outputLatency + ioBuffer + cueOnsetMs`.
/// Without a file (TTS) or over Bluetooth, the time is approximate.
public enum CueTiming {
    public static func delay(onsetMs: Double?, outputLatencyMs: Double, ioBufferMs: Double, bluetooth: Bool) -> (ms: Double, approximate: Bool) {
        guard let onsetMs else { return (0, true) }
        return (outputLatencyMs + ioBufferMs + onsetMs, bluetooth)
    }
}

#if canImport(AVFoundation) && os(iOS)
import AVFoundation

/// Cue sounds scheduled ahead on the host clock (T3.3, specs/02 "Saat tabanı"); the files of the
/// language's `cues.json`. A cue without a file is not scheduled here (the caller falls back to TTS).
@MainActor public final class CueOut {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let manifest: CueManifest
    private let dir: URL?
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var connectedFormat: AVAudioFormat?

    /// - Parameter dir: `audio/<lang>` in the bundle, if it exists.
    public init(dir: URL?) {
        self.dir = dir
        manifest = dir.flatMap { try? Data(contentsOf: $0.appendingPathComponent("cues.json")) }.flatMap { try? CueManifest.parse($0) }
            ?? CueManifest(cues: [:])
        engine.attach(player)
    }

    public func hasSound(_ key: String) -> Bool { manifest.cues[key] != nil && dir != nil }

    private var session: AVAudioSession { .sharedInstance() }

    public var isBluetooth: Bool {
        session.currentRoute.outputs.contains { [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE].contains($0.portType) }
    }

    /// The delay to the audible cue and whether it is approximate (read at cue time, specs/05).
    public func cueDelay(_ key: String) -> (ms: Double, approximate: Bool) {
        CueTiming.delay(onsetMs: hasSound(key) ? manifest.cues[key]?.cueOnsetMs : nil, outputLatencyMs: session.outputLatency * 1000,
                        ioBufferMs: session.ioBufferDuration * 1000, bluetooth: isBluetooth)
    }

    /// Schedules the cue at a host time (ms); false when it has no file or the engine cannot start.
    @discardableResult
    public func schedule(_ key: String, atMs: Double) -> Bool {
        guard let buffer = buffer(key) else { return false }
        if connectedFormat != buffer.format {
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
            connectedFormat = buffer.format
        }
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return false }
        player.scheduleBuffer(buffer, at: AVAudioTime(hostTime: HostClock.hostTicks(fromMs: atMs)), options: [], completionHandler: nil)
        if !player.isPlaying { player.play() }
        return true
    }

    /// Safety pause (specs/05): every scheduled or playing cue stops.
    public func stopAll() {
        player.stop()
    }

    public func shutdown() {
        player.stop()
        engine.stop()
    }

    private func buffer(_ key: String) -> AVAudioPCMBuffer? {
        if let b = buffers[key] { return b }
        guard let dir, let cue = manifest.cues[key], let file = try? AVAudioFile(forReading: dir.appendingPathComponent(cue.file)),
              let b = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: b)) != nil else { return nil }
        buffers[key] = b
        return b
    }
}
#endif
