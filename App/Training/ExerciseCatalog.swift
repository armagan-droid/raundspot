import Foundation
import SoloEngine

/// The templates in the bundle's `exercises/` (copied at build time, specs/02),
/// loaded for Vision 2D (H2). Templates the pose pipeline cannot serve are
/// rejected by the loader and not listed (specs/03).
enum ExerciseCatalog {
    static func load() -> [LoadedRulePack] {
        guard let dir = Bundle.main.url(forResource: "exercises", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        return files.filter { $0.pathExtension == "json" }
            .compactMap { url in (try? Data(contentsOf: url)).flatMap { try? RulePackLoader.load(data: $0, capabilities: .vision19TwoD).get() } }
            .sorted { order($0.pack.id) < order($1.pack.id) }
    }

    /// The template's demo animation, if the bundle has one (specs/04).
    static func demo(for id: String) -> ExerciseDemo? {
        guard let url = Bundle.main.url(forResource: id, withExtension: "json", subdirectory: "exercises/demos"),
              let json = try? JSONValue.parse(contentsOf: url) else { return nil }
        return try? ExerciseDemo.parse(json)
    }

    /// The bundle does not change while the app runs: loaded once.
    private static let cached = load()

    static func pack(_ id: String) -> LoadedRulePack? { cached.first { $0.pack.id == id } }

    static let eskivIds = ["slip_left", "slip_right", "slip", "duck", "bob_weave_left", "bob_weave_right", "lean_back"]

    /// Ready-made workouts (specs/06) whose templates all load.
    static func workouts(_ packs: [LoadedRulePack]) -> [Workout] {
        guard let dir = Bundle.main.url(forResource: "exercises/workouts", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        let ids = Set(packs.map(\.pack.id))
        let order = ["eskiv_temeli", "refleks", "kondisyon", "hizli_karma"]
        return files.filter { $0.pathExtension == "json" }
            .compactMap { (try? JSONValue.parse(contentsOf: $0)).flatMap { try? Workout.parse($0) } }
            .filter { w in w.blocks.allSatisfy { $0.exerciseId.map(ids.contains) ?? true } && w.choices.allSatisfy { $0.from.allSatisfy(ids.contains) } }
            .sorted { (order.firstIndex(of: $0.id) ?? 99) < (order.firstIndex(of: $1.id) ?? 99) }
    }

    /// The bundle's reflex catalog (specs/05), nil if missing or invalid.
    static func reflexCatalog(_ id: String = "muay_thai") -> ReflexCatalog? {
        guard let url = Bundle.main.url(forResource: id, withExtension: "json", subdirectory: "exercises/reflex"),
              let json = try? JSONValue.parse(contentsOf: url) else { return nil }
        return try? ReflexCatalog.parse(json).get()
    }

    /// AC-5.8: TestFlight and development builds run a draft catalog (labelled); the App Store build only an approved one.
    static var isReleaseBuild: Bool {
        #if DEBUG || BETA
        false
        #else
        true
        #endif
    }

    /// A guided step's demo (specs/04 "Adım gösterimleri").
    static func stepDemo(for key: String) -> ExerciseDemo? {
        guard let url = Bundle.main.url(forResource: key, withExtension: "json", subdirectory: "exercises/demos/steps"),
              let json = try? JSONValue.parse(contentsOf: url) else { return nil }
        return try? ExerciseDemo.parse(json)
    }

    /// Eskivs first, then conditioning (specs/04 "Şablon seti").
    private static func order(_ id: String) -> String {
        return eskivIds.firstIndex(of: id).map { String(format: "0%02d", $0) } ?? "1" + id
    }
}

/// The user's language for template texts: Turkish when the system language is Turkish.
enum Lang {
    static var isTurkish: Bool { Locale.current.language.languageCode?.identifier == "tr" }
    static var code: String { isTurkish ? "tr" : "en" }
    static func text(_ t: LocalizedText) -> String { isTurkish ? t.tr : t.en }
}
