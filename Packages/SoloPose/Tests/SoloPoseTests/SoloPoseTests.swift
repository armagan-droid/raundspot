import Testing
@testable import SoloPose

@Suite struct SoloPoseTests {
    @Test func moduleLoads() {
        #expect(SoloPose.moduleName == "SoloPose")
    }
}
