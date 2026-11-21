import Testing
@testable import SoloCapture

@Suite struct SoloCaptureTests {
    @Test func moduleLoads() {
        #expect(SoloCapture.moduleName == "SoloCapture")
    }
}
