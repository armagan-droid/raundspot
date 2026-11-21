import Testing
@testable import SoloEngine

@Suite struct SoloEngineTests {
    @Test func generatedByCarriesVersion() {
        #expect(SoloEngine.generatedBy == "SoloEngine \(SoloEngine.version)")
    }
}
