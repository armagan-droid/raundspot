import Foundation
import Testing

/// specs/00 rule 8: every user-visible string is in the String Catalog and a
/// missing translation is a test failure (also AC-12.5).
///
/// The test reads the catalog as compiled into the host app bundle
/// (`<lang>.lproj/Localizable.strings` and `.stringsdict`), not the source
/// `.xcstrings` file: a simulator process may not read the repository checkout
/// (e.g. on an external volume). When compiling, Xcode omits a key that has no
/// translation for a language and emits an empty value for one in state `new`;
/// both are caught here.
@Suite struct StringCatalogTests {
    static let sourceLanguage = "en"
    static let requiredLanguages = ["en", "tr"]
    static let tables = ["Localizable"]

    @Test func everyKeyIsTranslatedInEveryLanguage() throws {
        for table in Self.tables {
            let source = try Self.compiledStrings(table: table, language: Self.sourceLanguage)
            #expect(!source.isEmpty, "\(table): no compiled strings for \(Self.sourceLanguage)")
            for language in Self.requiredLanguages {
                let translated = try Self.compiledStrings(table: table, language: language)
                let missing = source.keys.filter { (translated[$0] ?? "").isEmpty }.sorted()
                #expect(missing.isEmpty, "\(table) [\(language)] missing translations: \(missing)")
            }
        }
    }

    @Test func appNameKeyExists() {
        #expect(!String(localized: "app.name").isEmpty)
        #expect(String(localized: "app.name") != "app.name")
    }

    /// Keys of `<table>.strings` plus `<table>.stringsdict` for one language.
    /// A plural/variation entry counts as translated when it is present.
    static func compiledStrings(table: String, language: String) throws -> [String: String] {
        let bundle = Bundle.main
        guard let lproj = bundle.path(forResource: language, ofType: "lproj") else {
            Issue.record("no \(language).lproj in \(bundle.bundlePath)")
            return [:]
        }
        var result: [String: String] = [:]
        let stringsURL = URL(fileURLWithPath: lproj).appendingPathComponent("\(table).strings")
        if let dict = NSDictionary(contentsOf: stringsURL) as? [String: String] {
            result.merge(dict) { current, _ in current }
        }
        let dictURL = URL(fileURLWithPath: lproj).appendingPathComponent("\(table).stringsdict")
        if let dict = NSDictionary(contentsOf: dictURL) as? [String: Any] {
            for key in dict.keys { result[key] = result[key] ?? "<plural>" }
        }
        return result
    }
}
