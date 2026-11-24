import Foundation
import Testing
@testable import SoloEngine

/// Source golden under `fixtures/source-golden/` (specs/03 "Kaynak uyumluluğu"):
/// produced once from the TypeScript engine at c2fe3fd by tools/golden-export.
/// The files are never edited; cases this project changes on purpose are listed
/// in `superseded.json` with their spec section and are skipped.
enum SourceGolden {
    static let dir = Repo.root.appendingPathComponent("fixtures/source-golden", isDirectory: true)
    static let commit = "c2fe3fd"
    static let nonCaseFiles: Set<String> = ["expressions.json", "superseded.json"]

    static var caseFiles: [String] {
        Repo.jsonFiles(in: dir).map(\.lastPathComponent).filter { !nonCaseFiles.contains($0) }
    }

    /// `{ "superseded": [ { "file", "spec", "reason" } ] }`; absent means none.
    static func superseded() throws -> Set<String> {
        let url = dir.appendingPathComponent("superseded.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let list = try Repo.read(url)["superseded"]?.arrayValue ?? []
        return Set(list.compactMap { entry in
            entry["spec"]?.stringValue != nil && entry["reason"]?.stringValue != nil ? entry["file"]?.stringValue : nil
        })
    }

    static func source(of o: JSONValue) -> (repo: String?, commit: String?) {
        (o["source"]?["repo"]?.stringValue, o["source"]?["commit"]?.stringValue)
    }
}

@Suite("Source conformance (specs/03, AC-3.2)")
struct SoloEngineSourceConformanceTests {
    @Test("the golden exists and covers every source template")
    func coverage() throws {
        let files = SourceGolden.caseFiles
        #expect(!files.isEmpty, "fixtures/source-golden is missing: tools/golden-export/run.sh (once, specs/03)")
        let packs = Set(files.compactMap { $0.split(separator: ".").first.map(String.init) })
        let templates = Set(Repo.jsonFiles(in: Repo.sourceExercises).map { $0.deletingPathExtension().lastPathComponent })
        #expect(packs == templates)
    }

    @Test("superseded entries name existing case files and give a spec section and reason")
    func supersededList() throws {
        let url = SourceGolden.dir.appendingPathComponent("superseded.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let list = try #require(try Repo.read(url)["superseded"]?.arrayValue)
        for entry in list {
            let file = try #require(entry["file"]?.stringValue)
            #expect(SourceGolden.caseFiles.contains(file), "\(file)")
            #expect(entry["spec"]?.stringValue?.isEmpty == false && entry["reason"]?.stringValue?.isEmpty == false, "\(file)")
        }
    }

    @Test("Swift engine reproduces the source engine", arguments: SourceGolden.caseFiles)
    func conformance(file: String) throws {
        guard try !SourceGolden.superseded().contains(file) else { return }
        let json = try Repo.read(SourceGolden.dir.appendingPathComponent(file))
        #expect(SourceGolden.source(of: json).commit == SourceGolden.commit)
        let golden = try EngineCase(json: json)
        let loaded = try Repo.load(golden.rulePack)
        #expect(loaded.pack.version == golden.rulePackVersion)
        let seqURL = SourceGolden.dir.appendingPathComponent(golden.sequence)
        let seq = try LandmarkSequence.parse(data: Data(contentsOf: seqURL)).get()
        let actual = EngineCase.run(loaded, seq, setup: golden.setup, options: golden.options,
                                    cuesEnabled: golden.cuesEnabled, metricsEvery: golden.expected.metricsEvery)
        let diff = EngineCase.differences(expected: golden.expected, actual: actual)
        #expect(diff.isEmpty, "\(file) differs from the source engine:\n\(diff.joined(separator: "\n"))")
        // event times are the frame times (specs/03 "Zaman damgalı olaylar")
        for e in golden.expected.events { #expect(e.t == seq.frames[e.frame].t, "\(file) event at frame \(e.frame)") }
    }
}

@Suite("Expression golden (specs/03, AC-3.3)")
struct ExpressionGoldenTests {
    struct Entry: CustomTestStringConvertible, Sendable {
        var index: Int
        var json: JSONValue
        var testDescription: String {
            "#\(index) \(json["form"]?.stringValue ?? "?") \(json["src"]?.stringValue.map { "\"\($0)\"" } ?? "?")"
        }
    }

    static var entries: [Entry] {
        let url = SourceGolden.dir.appendingPathComponent("expressions.json")
        let list = (try? Repo.read(url))?["expressions"]?.arrayValue ?? []
        return list.enumerated().map { Entry(index: $0.offset, json: $0.element) }
    }

    @Test("the expression golden exists and is from the source commit")
    func header() throws {
        let json = try Repo.read(SourceGolden.dir.appendingPathComponent("expressions.json"))
        #expect(SourceGolden.source(of: json).commit == SourceGolden.commit)
        #expect(json["nullMeans"]?.stringValue == "NaN")
        #expect(!Self.entries.isEmpty)
    }

    @Test("parse error or three-valued result matches the source", arguments: entries)
    func entry(_ e: Entry) throws {
        let o = e.json
        let src = try #require(o["src"]?.stringValue)
        let form = try #require(o["form"]?.stringValue)
        let metrics: Set<String>? = o["metrics"] == .null ? nil : Set(try #require(o["metrics"]?.arrayValue).compactMap(\.stringValue))

        let parsed: Result<(expr: Expr, position: String?, durationMs: Int?), ExpressionError>
        do throws(ExpressionError) {
            switch form {
            case "check":
                let c = try ExpressionParser.parseCheck(src, metrics: metrics)
                parsed = .success((c.expr, c.position.rawValue, nil))
            case "readyPose":
                let r = try ExpressionParser.parseReadyPose(src, metrics: metrics)
                parsed = .success((r.expr, nil, r.durationMs))
            default:
                parsed = .success((try ExpressionParser.parseExpression(src, metrics: metrics), nil, nil))
            }
        } catch {
            parsed = .failure(error)
        }

        if let expected = o["error"] {
            let reason = try #require(expected["reason"]?.stringValue)
            let column = try #require(expected["column"]?.numberValue)
            switch parsed {
            case .success: Issue.record("expected \(reason) (column \(Int(column))), parsed")
            case .failure(let error):
                #expect(error.reason == reason)
                #expect(error.column == Int(column))
            }
            return
        }
        guard case .success(let p) = parsed else {
            if case .failure(let error) = parsed { Issue.record("source parses it; Swift: \(error)") }
            return
        }
        #expect(p.position == o["position"]?.stringValue)
        #expect(p.durationMs == o["durationMs"]?.numberValue.map { Int($0) })
        for (i, r) in try #require(o["results"]?.arrayValue).enumerated() {
            var values: [String: Double] = [:]
            for (k, v) in try #require(r["values"]?.objectValue).entries { values[k] = v == .null ? .nan : v.numberValue }
            let truth: Bool? = switch r["truth"] { case .bool(let b)?: b; default: nil }
            #expect(r["truth"] == .bool(true) || r["truth"] == .bool(false) || r["truth"]?.stringValue == "unknown")
            #expect(p.expr.evaluate(values) == truth, "results[\(i)]")
        }
    }
}
