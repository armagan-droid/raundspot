import Foundation
import SoloCapture
import SoloEngine
import Testing
@testable import GymSpotSolo

/// Counts every request the app's URL loading would make (specs/10 rule 3).
final class CountingProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var count = 0
    override class func canInit(with request: URLRequest) -> Bool {
        count += 1
        return false
    }
}

/// specs/10: AC-10.1 (no request while training) and AC-10.5 (the manifest ships in the app).
@MainActor @Suite(.serialized) struct PrivacyTests {
    @Test func aWorkoutMakesNoNetworkRequest() async throws {
        URLProtocol.registerClass(CountingProtocol.self)
        defer { URLProtocol.unregisterClass(CountingProtocol.self) }
        CountingProtocol.count = 0
        let clock = ManualClock()
        let seq = try FakeCameraTests.slips()
        let source = SequenceFrameSource(sequence: seq, clock: clock)
        let model = TrainingModel(single: try #require(ExerciseCatalog.pack("slip_left")), source: source, clock: clock)
        defer { model.close() }
        await model.confirmSpace()
        for _ in 0..<600 {
            clock.advance(byMs: 1000 / seq.fps)
            source.pump()
            model.tick()
            if model.state == .ready { model.act(.start) }
        }
        #expect(model.snapshot.counted > 0)
        #expect(CountingProtocol.count == 0)
    }

    @Test func thePrivacyManifestShipsWithoutTracking() throws {
        let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let plist = try #require(NSDictionary(contentsOf: url))
        #expect(plist["NSPrivacyTracking"] as? Bool == false)
        #expect((plist["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
        let types = (plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []).compactMap { $0["NSPrivacyAccessedAPIType"] as? String }
        #expect(types.contains("NSPrivacyAccessedAPICategorySystemBootTime"))
    }
}
