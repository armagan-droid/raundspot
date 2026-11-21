import Foundation
import Testing

/// The tests are hosted by the app, so `Bundle.main` is GymSpotSolo.app.
@Suite struct InfoPlistTests {
    /// AC-2.5: the app never asks for the microphone (also AC-9.9, specs/10).
    @Test func noMicrophoneUsageDescription() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") == nil)
    }

    /// AC-2.3 (runtime side): the App Store target is not built with recording mode.
    @Test func hostAppIsNotTheBetaTarget() {
        #expect(Bundle.main.executableURL?.lastPathComponent == "GymSpotSolo")
    }
}
