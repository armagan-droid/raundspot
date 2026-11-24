import Foundation
import Testing
@testable import SoloEngine

/// specs/05 "İşaret kataloğu", "Seviye kaydı ve doğrulama" (T4.1; AC-5.3, AC-5.6, AC-5.8).
@Suite("Reflex catalog") struct ReflexCatalogTests {
    static func json() throws -> JSONValue { try Repo.read(Repo.exercises.appendingPathComponent("reflex/muay_thai.json")) }
    static func load(_ j: JSONValue) -> Result<ReflexCatalog, CatalogIssues> { ReflexCatalog.parse(j) }

    @Test func theDraftCatalogLoads() throws {
        let c = try Self.load(Self.json()).get()
        #expect(c.id == "muay_thai" && c.version == 1 && c.status == .draft)
        #expect(c.responses == ["slip_left", "slip_right", "duck", "bob_weave_left", "bob_weave_right"])
        #expect(c.strikes.map(\.id) == ["jab", "cross", "lead_hook", "rear_hook"])
        #expect(c.feints.map(\.id) == ["stop"])
        #expect(c.levels.map(\.level) == [1, 2, 3, 4, 5, 6])
        let l1 = c.levels[0]
        #expect(l1.strikes == ["jab", "cross"] && l1.foreMs == 2000...4000 && l1.windowMs == 1500 && l1.comboLen == 1...1)
        #expect(l1.comboGapMs == nil && l1.feintRate == 0 && l1.cues == 15)
        #expect(c.levels[5].comboGapMs == 450 && c.levels[5].feintRate == 0.2)
        // no high_kick: H1 is not verified (specs/05 table)
        #expect(!c.strikes.contains { $0.id == "high_kick" })
    }

    // MARK: rejection

    static var bad: [(String, (inout JSONValue) -> Void)] { [
        ("unknown field", { $0["extra"] = 1 }),
        ("status", { $0["status"] = "final" }),
        ("opponent stance", { $0["assumes"]!["opponentStance"] = "southpaw" }),
        ("empty responses", { $0["responses"] = [] }),
        ("duplicate response", { $0["responses"] = ["slip_left", "slip_left"] }),
        ("specificity pair of one", { $0["specificity"]![0] = ["duck", "duck"] }),
        ("specificity outside responses", { $0["specificity"]![0] = ["duck", "lean_back"] }),
        ("accept outside responses", { $0["strikes"]![0]!["accept"] = ["slip_right", "lean_back"] }),
        ("empty accept", { $0["strikes"]![0]!["accept"] = [] }),
        ("prefer outside accept", { $0["strikes"]![0]!["prefer"] = "duck" }),
        ("duplicate strike", { $0["strikes"]![1]!["id"] = "jab" }),
        ("feint named like a strike", { $0["feints"]![0]!["id"] = "jab" }),
        ("empty say", { $0["strikes"]![0]!["say"]!["southpaw"] = "" }),
        ("levels not from 1", { $0["levels"]![0]!["level"] = 0 }),
        ("levels with a gap", { $0["levels"]![1]!["level"] = 3 }),
        ("undefined strike in a level", { $0["levels"]![0]!["strikes"] = ["jab", "uppercut"] }),
        ("fore time inverted", { $0["levels"]![0]!["foreSec"] = [4.0, 2.0] }),
        ("fore time zero", { $0["levels"]![0]!["foreSec"] = [0, 2.0] }),
        ("window zero", { $0["levels"]![0]!["windowMs"] = 0 }),
        ("combo length zero", { $0["levels"]![2]!["comboLen"] = [0, 2] }),
        ("combo gap missing", { $0["levels"]![2]!["comboGapMs"] = nil }),
        ("combo gap without combos", { $0["levels"]![0]!["comboGapMs"] = 500 }),
        ("feint rate 1", { $0["levels"]![3]!["feintRate"] = 1 }),
        ("feints needed", { $0["feints"] = [] }),
        ("no cues", { $0["levels"]![0]!["cues"] = 0 }),
    ] }

    @Test(arguments: bad.indices) func malformedCatalogsAreRejected(_ i: Int) throws {
        let (name, edit) = Self.bad[i]
        var j = try Self.json()
        edit(&j)
        #expect(throws: CatalogIssues.self, "\(name)") { try Self.load(j).get() }
    }

    // MARK: AC-5.3 southpaw

    @Test func southpawMirrorsTheResponsesAndTheSpokenNames() throws {
        let c = try Self.load(Self.json()).get()
        let o = c.resolved(for: .orthodox), s = c.resolved(for: .southpaw)
        let table: [(String, say: String, accept: [String], prefer: String)] = [
            ("jab", "strike.jab", ["slip_left", "slip_right"], "slip_left"),
            ("cross", "strike.cross", ["slip_right", "slip_left"], "slip_right"),
            ("lead_hook", "strike.right_hook", ["bob_weave_right", "duck"], "bob_weave_right"),
            ("rear_hook", "strike.left_hook", ["bob_weave_left", "duck"], "bob_weave_left"),
        ]
        for row in table {
            let strike = try #require(s.strikes.first { $0.id == row.0 })
            #expect(strike.say == row.say && strike.accept == row.accept && strike.prefer == row.prefer, "\(row.0)")
        }
        #expect(o.strikes.first { $0.id == "lead_hook" }?.say == "strike.left_hook")
        #expect(o.strikes.first { $0.id == "jab" }?.prefer == "slip_right")
        // each pair mirrored: bob_weave_left over slip_left becomes bob_weave_right over slip_right
        #expect(s.specificity.map(\.more) == o.specificity.map { ReflexCatalog.mirrored($0.more) })
        #expect(s.specificity.map(\.less) == o.specificity.map { ReflexCatalog.mirrored($0.less) })
        #expect(s.isMoreSpecific("bob_weave_right", than: "duck") && !s.isMoreSpecific("duck", than: "bob_weave_right"))
        #expect(s.feints.map(\.say) == ["strike.stop"])
        #expect(Set(s.responses) == Set(o.responses))
    }

    @Test func mirroringSwapsSidesOnly() {
        #expect(ReflexCatalog.mirrored("slip_left") == "slip_right")
        #expect(ReflexCatalog.mirrored("bob_weave_right") == "bob_weave_left")
        #expect(ReflexCatalog.mirrored("duck") == "duck")
        #expect(ReflexCatalog.mirrored("lean_back_front") == "lean_back_front")
    }

    // MARK: AC-5.6 combo gap

    @Test func aComboGapShorterThanTheSlowestResponseIsRejected() throws {
        let c = try Self.load(Self.json()).get()
        let min = ["slip_left": 200, "slip_right": 200, "duck": 250, "bob_weave_left": 250, "bob_weave_right": 250]
        #expect(c.templateIssues(minDurationMs: min).isEmpty)
        var j = try Self.json()
        j["levels"]![5]!["comboGapMs"] = 240
        let short = try Self.load(j).get()
        let issues = short.templateIssues(minDurationMs: min)
        #expect(issues.count == 1 && issues[0].path == "levels.5.comboGapMs")
        // a response without a template
        var m = min
        m["duck"] = nil
        #expect(c.templateIssues(minDurationMs: m).contains { $0.path == "responses.2" })
    }

    // MARK: AC-5.8 (engine side)

    @Test func releaseRunsOnlyApprovedCatalogs() throws {
        let draft = try Self.load(Self.json()).get()
        #expect(draft.isUsable(release: false) && !draft.isUsable(release: true))
        var j = try Self.json()
        j["status"] = "approved"
        #expect(try Self.load(j).get().isUsable(release: true))
    }
}
