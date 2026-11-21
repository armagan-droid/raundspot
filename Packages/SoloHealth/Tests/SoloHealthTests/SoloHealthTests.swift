import Testing
@testable import SoloHealth

@Suite struct SoloHealthTests {
    @Test func moduleLoads() {
        #expect(SoloHealth.moduleName == "SoloHealth")
    }
}
