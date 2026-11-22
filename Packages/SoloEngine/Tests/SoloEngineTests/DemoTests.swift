import Foundation
import Testing
@testable import SoloEngine
import SoloEngineTesting

// specs/04 "Gösterim animasyonu", AC-4.10. `UPDATE_DEMOS=1 swift test …`
// rewrites exercises/demos/ from the generator.

private let demosDir = Repo.exercises.appendingPathComponent("demos", isDirectory: true)
private let ids = DemoGenerator.repsPerLoop.keys.sorted()

@Suite("Demo animations (AC-4.10)") struct DemoTests {
    @Test(arguments: ids) func fileMatchesTheGenerator(_ id: String) throws {
        let generated = try #require(DemoGenerator.demo(id))
        let url = demosDir.appendingPathComponent("\(id).json")
        if ProcessInfo.processInfo.environment["UPDATE_DEMOS"] == "1" {
            try FileManager.default.createDirectory(at: demosDir, withIntermediateDirectories: true)
            try Data((generated.json.serialized() + "\n").utf8).write(to: url, options: .atomic)
        }
        let stored = try ExerciseDemo.parse(JSONValue.parse(contentsOf: url))
        #expect(stored == generated)
    }

    @Test(arguments: ids) func oneLoopIsCorrectReps(_ id: String) throws {
        let demo = try ExerciseDemo.parse(JSONValue.parse(contentsOf: demosDir.appendingPathComponent("\(id).json")))
        #expect(demo.exercise == id && demo.step == nil)
        let loaded = try RulePackLoader.load(Repo.read(Repo.exercises.appendingPathComponent("\(id).json")), capabilities: .vision19TwoD).get()
        #expect(loaded.pack.camera.views.contains(demo.view))
        let n = demo.frames.count
        let frames = (0..<(2 * n)).map { demo.frame($0 % n, t: Double($0 * demo.frameMs)) }
        let near: PersonSide = demo.view == .side ? chooseNearSide(frames) : .left
        let engine = ExerciseEngine(loaded, setup: ExerciseSetup(view: View(demo.view), nearSide: near))
        var outcomes: [RepOutcome] = []
        var faults: [String] = []
        for f in frames {
            for e in engine.push(f) {
                switch e.event {
                case .repCompleted(let o, let fs, _): outcomes.append(o); faults += fs
                case .faultDetected(let id): faults.append(id)
                default: break
                }
            }
        }
        #expect(outcomes == Array(repeating: .valid, count: 2 * DemoGenerator.repsPerLoop[id]!), "\(id)")
        #expect(faults.isEmpty, "\(id): \(faults)")
    }

    @Test func everyTemplateHasADemoAndEveryDemoATemplate() throws {
        let templates = try FileManager.default.contentsOfDirectory(atPath: Repo.exercises.path).filter { $0.hasSuffix(".json") }
        let demos = try FileManager.default.contentsOfDirectory(atPath: demosDir.path).filter { $0.hasSuffix(".json") }
        #expect(Set(templates) == Set(demos))
        #expect(Set(ids.map { "\($0).json" }) == Set(templates))
    }

    @Test func depthMovesHaveASideViewWithTheSameTiming() throws {
        for id in ids {
            let demo = try #require(DemoGenerator.demo(id))
            if DemoGenerator.extraSideView.contains(id) {
                let extra = try #require(demo.extra, "\(id)")
                #expect(extra.view == .side && extra.frames.count == demo.frames.count)
                // the side view shows the forward lean the front view cannot: the nose moves forward of the hips
                let f0 = extra.frames[0], deep = extra.frames.max { $0[.nose]!.y < $1[.nose]!.y }!
                #expect(abs(deep[.nose]!.x - deep[.leftHip]!.x) > abs(f0[.nose]!.x - f0[.leftHip]!.x) + 0.03, "\(id)")
            } else {
                #expect(demo.extra == nil, "\(id)")
            }
        }
    }

    @Test func guideMarksFollowTheDemo() throws {
        for id in ["duck", "bob_weave_left", "slip_left", "squat", "jumping_jack"] {
            let demo = try #require(DemoGenerator.demo(id))
            let loaded = try RulePackLoader.load(Repo.read(Repo.exercises.appendingPathComponent("\(id).json")), capabilities: .vision19TwoD).get()
            let g = demo.guides(loaded)
            #expect(g.count == demo.frames.count)
            let modes = g.compactMap { $0.head?.mode ?? $0.line?.mode }
            #expect(modes.count == g.count && modes.contains(.go) && modes.contains(.back), "\(id)")
        }
    }

    @Test(arguments: StepDemos.all.keys.sorted()) func stepDemoFileMatchesTheGenerator(_ key: String) throws {
        let generated = try #require(StepDemos.demo(key))
        let dir = demosDir.appendingPathComponent("steps", isDirectory: true)
        let url = dir.appendingPathComponent("\(key).json")
        if ProcessInfo.processInfo.environment["UPDATE_DEMOS"] == "1" {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data((generated.json.serialized() + "\n").utf8).write(to: url, options: .atomic)
        }
        let stored = try ExerciseDemo.parse(JSONValue.parse(contentsOf: url))
        #expect(stored == generated && stored.step == key && stored.exercise == nil)
        #expect(stored.loopMs >= 1500 && stored.loopMs <= 6000, "a short loop")
    }

    @Test func everyWorkoutStepHasADemo() throws {
        let dir = Repo.exercises.appendingPathComponent("workouts")
        var keys = Set<String>()
        for f in try FileManager.default.contentsOfDirectory(atPath: dir.path) where f.hasSuffix(".json") {
            for b in try Workout.parse(Repo.read(dir.appendingPathComponent(f))).blocks { keys.formUnion(b.steps.map(\.textKey)) }
        }
        #expect(!keys.isEmpty)
        let stored = Set(try FileManager.default.contentsOfDirectory(atPath: demosDir.appendingPathComponent("steps").path)
            .filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) })
        #expect(keys.subtracting(stored).isEmpty, "steps without a demo: \(keys.subtracting(stored).sorted())")
        #expect(stored.subtracting(keys).isEmpty, "demos for no step: \(stored.subtracting(keys).sorted())")
    }

    @Test func stepRigMovesWhatTheStepSays() throws {
        func frames(_ k: String) throws -> [[LandmarkName: GuidePoint]] { try #require(StepDemos.demo(k)).frames }
        // jumps: the ankles leave the floor
        let jumps = try frames("warmup.light_jumps")
        #expect(jumps.map { $0[.leftAnkle]!.y }.min()! < jumps[0][.leftAnkle]!.y - 0.03)
        // arm circles: the wrist goes above the head
        let circles = try frames("warmup.arm_circles")
        #expect(circles.contains { $0[.leftWrist]!.y < $0[.nose]!.y })
        // breathing: wrists above the shoulders at the top
        let breathe = try frames("cooldown.breathing")
        #expect(breathe.contains { $0[.leftWrist]!.y < $0[.leftShoulder]!.y })
        // leg swings: the right ankle moves well forward and back
        let swing = try frames("warmup.dynamic_stretch").map { $0[.rightAnkle]!.x }
        #expect(swing.max()! - swing.min()! > 0.15)
    }

    @Test func interpolatesAndLoops() throws {
        let demo = try #require(DemoGenerator.demo("squat"))
        let a = demo.frames[3][.nose]!, b = demo.frames[4][.nose]!
        let mid = demo.pose(atMs: 3.5 * Double(demo.frameMs))[.nose]!
        #expect(abs(mid.y - (a.y + b.y) / 2) < 1e-12)
        #expect(demo.pose(atMs: demo.loopMs + 100) == demo.pose(atMs: 100))
    }

    @Test func rejectsMalformedFiles() throws {
        let good = try #require(DemoGenerator.demo("duck")).json
        func rejects(_ edit: (inout JSONValue) -> Void, _ fragment: String) {
            var j = good
            edit(&j)
            #expect(throws: ExerciseDemo.ParseError.self) { try ExerciseDemo.parse(j) }
            do { _ = try ExerciseDemo.parse(j) } catch { #expect(error.description.contains(fragment), "\(error)") }
        }
        rejects({ $0["formatVersion"] = 2 }, "formatVersion")
        rejects({ $0["view"] = "top" }, "view")
        rejects({ $0["bogus"] = true }, "unknown field")
        rejects({ $0["frameMs"] = 0 }, "frameMs")
        rejects({ $0["frames"]![0]!["left_heel"] = [0.1, 0.2] }, "vision19")
        rejects({ $0["frames"]![0]!["nose"] = [0.1] }, "[x, y]")
        rejects({ $0["step"] = "warmup.x" }, "exactly one of exercise and step")
        rejects({ let e: JSONValue = ["view": "side", "frames": []]; $0["extra"] = e }, "as many frames")
        rejects({ let e: JSONValue = ["view": "side", "frames": $0["frames"]!, "x": 1]; $0["extra"] = e }, "unknown field")
    }
}
