import Foundation
import Testing
@testable import SoloEngine

/// specs/00 rule 8: every String Catalog key the data names (reflex cues,
/// workout steps) is in `App/Resources/Localizable.xcstrings` with TR and EN.
@Suite("Data keys in the String Catalog") struct DataKeysTests {
    static func catalogKeys() throws -> [String: Set<String>] {
        let url = Repo.root.appendingPathComponent("App/Resources/Localizable.xcstrings")
        var out: [String: Set<String>] = [:]
        for (key, entry) in try Repo.read(url)["strings"]?.objectValue?.entries ?? [] {
            let langs = entry["localizations"]?.objectValue?.entries.filter { $0.value["stringUnit"]?["value"]?.stringValue?.isEmpty == false }
            out[key] = Set((langs ?? []).map(\.key))
        }
        return out
    }

    static func dataKeys() throws -> [String] {
        var keys: [String] = []
        for f in Repo.jsonFiles(in: Repo.exercises.appendingPathComponent("reflex")) {
            let c = try ReflexCatalog.parse(Repo.read(f)).get()
            keys += c.strikes.flatMap { $0.say.values } + c.feints.map(\.say)
        }
        for f in Repo.jsonFiles(in: Repo.exercises.appendingPathComponent("workouts")) {
            keys += try Workout.parse(Repo.read(f)).blocks.flatMap { $0.steps.map(\.textKey) }
        }
        return Array(Set(keys)).sorted()
    }

    @Test func everyKeyTheDataNamesIsTranslated() throws {
        let catalog = try Self.catalogKeys()
        let keys = try Self.dataKeys()
        #expect(keys.contains("strike.jab") && keys.contains("warmup.arm_circles"))
        for key in keys { #expect(catalog[key] == ["en", "tr"], "\(key)") }
    }
}
