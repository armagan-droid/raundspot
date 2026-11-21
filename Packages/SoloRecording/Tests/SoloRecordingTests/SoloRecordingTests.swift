import Testing
@testable import SoloRecording

@Suite struct SoloRecordingTests {
    @Test func moduleLoads() {
        #expect(SoloRecording.moduleName == "SoloRecording")
    }
}
