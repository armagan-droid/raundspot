import Foundation
import Testing
@testable import SoloEngine

/// specs/00 rule 6, specs/07 "Dil kuralları", AC-7.4: no forbidden health phrase in the String Catalog,
/// TR and EN, any case, stems at a word start (so inflections match: "teşhisi", "treated").
@Suite("Forbidden phrases (AC-7.4)") struct ForbiddenPhraseTests {
    static let tr = ["teşhis", "bozukluk", "hastalı", "hastalık", "skolyoz", "kifoz", "lordoz", "düz boyun", "tedavi", "düzeltir",
                     "iyileştirir", "ağrıyı giderir", "anormal"]
    static let en = ["diagnos", "disorder", "condition", "scoliosis", "kyphosis", "lordosis", "text neck", "treat", "cure", "fix",
                     "corrects", "heals", "relieves pain", "abnormal"]

    /// Whole words that start with a stem but are not the forbidden word (specs/07): "Conditioning" is the
    /// product's training kind, not a medical condition.
    static let allowedWords: Set<String> = ["conditioning"]

    static func values() throws -> [(key: String, lang: String, text: String)] {
        let url = Repo.root.appendingPathComponent("App/Resources/Localizable.xcstrings")
        var out: [(String, String, String)] = []
        for (key, entry) in try Repo.read(url)["strings"]?.objectValue?.entries ?? [] {
            for (lang, l) in entry["localizations"]?.objectValue?.entries ?? [] {
                if let v = l["stringUnit"]?["value"]?.stringValue { out.append((key, lang, v)) }
            }
        }
        return out
    }

    /// A stem at the start of a word (letters before it would make it part of another word).
    static func contains(_ text: String, stem: String) -> Bool {
        let t = text.lowercased(with: Locale(identifier: "tr")), s = stem.lowercased(with: Locale(identifier: "tr"))
        var from = t.startIndex
        while let r = t.range(of: s, range: from..<t.endIndex) {
            let atStart = r.lowerBound == t.startIndex || !t[t.index(before: r.lowerBound)].isLetter
            let wordEnd = t[r.lowerBound...].firstIndex { !$0.isLetter } ?? t.endIndex
            if atStart, !allowedWords.contains(String(t[r.lowerBound..<wordEnd])) { return true }
            from = r.upperBound
        }
        return false
    }

    @Test func noForbiddenPhrase() throws {
        var hits: [String] = []
        for v in try Self.values() {
            for stem in v.lang == "tr" ? Self.tr : Self.en where Self.contains(v.text, stem: stem) { hits.append("\(v.key) [\(v.lang)]: \(stem)") }
        }
        #expect(hits.isEmpty, "\(hits)")
    }

    @Test func theMatcherFindsStemsAtWordStartsOnly() {
        #expect(Self.contains("Teşhisi yok", stem: "teşhis"))
        #expect(Self.contains("It was treated", stem: "treat"))
        #expect(!Self.contains("a prefix here", stem: "fix"))
        #expect(!Self.contains("secure", stem: "cure"))
        #expect(!Self.contains("Conditioning", stem: "condition") && Self.contains("a heart condition", stem: "condition"))
    }
}
