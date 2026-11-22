#if canImport(AVFoundation) && os(iOS)
import AVFoundation

/// Spoken cues through the TTS fallback (T3.3 "TTS yedeği"). Audio session per
/// specs/02 "Ses oturumu": playback, ducks and mixes with the user's music, no microphone.
@MainActor public final class SpeechOut {
    private let synth = AVSpeechSynthesizer()
    public var language: String
    public var enabled = true

    public init(language: String) {
        self.language = language
    }

    public func activate() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default, options: [.duckOthers, .mixWithOthers])
        try? s.setActive(true)
    }

    public func deactivate() {
        synth.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Interrupts whatever is being said: a newer cue is more relevant.
    public func say(_ text: String) {
        guard enabled, !text.isEmpty else { return }
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: language == "tr" ? "tr-TR" : "en-US")
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        synth.speak(u)
    }
}
#endif
