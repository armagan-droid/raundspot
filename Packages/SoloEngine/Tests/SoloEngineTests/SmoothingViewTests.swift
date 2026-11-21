import Foundation
import Testing
@testable import SoloEngine
import SoloEngineTesting

// Ports of the source `engine/test/smoothing.test.ts` and `view.test.ts`
// (commit c2fe3fd), plus the synthetic generator's bit identity.

private let params = OneEuroParams(minCutoff: 1.0, beta: 0.05)
private let step = 1000.0 / 30

@Suite("OneEuroFilter") struct OneEuroFilterTests {
    @Test func firstSamplePassesThroughUnchanged() {
        var f = OneEuroFilter(params)
        #expect(f.filter(42, tMs: 0) == 42)
    }

    @Test func constantSignalStaysConstant() {
        var f = OneEuroFilter(params)
        for i in 0..<30 { #expect(Swift.abs(f.filter(10, tMs: Double(i) * step) - 10) < 0.005) }
    }

    @Test func reducesJitterOnANoisyConstantSignal() {
        var f = OneEuroFilter(params)
        let rng = SeededRandom(seed: 5)
        var raw: [Double] = [], out: [Double] = []
        for i in 0..<300 {
            let x = 120 + rng.gaussian(2)
            raw.append(x)
            out.append(f.filter(x, tMs: Double(i) * step))
        }
        func sd(_ xs: ArraySlice<Double>) -> Double {
            let m = xs.reduce(0, +) / Double(xs.count)
            return (xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count)).squareRoot()
        }
        #expect(sd(out[30...]) < sd(raw[30...]) * 0.6)
    }

    @Test func convergesAfterAStep() {
        var f = OneEuroFilter(params)
        _ = f.filter(0, tMs: 0)
        var y = 0.0
        for i in 1...60 { y = f.filter(100, tMs: Double(i) * step) }
        #expect(y > 99)
    }

    @Test func higherBetaLagsLessOnAFastRamp() {
        var slow = OneEuroFilter(OneEuroParams(minCutoff: 1, beta: 0))
        var fast = OneEuroFilter(OneEuroParams(minCutoff: 1, beta: 0.5))
        var ys = 0.0, yf = 0.0
        for i in 0..<15 {
            let x = Double(i) * 5  // 150°/s
            ys = slow.filter(x, tMs: Double(i) * step)
            yf = fast.filter(x, tMs: Double(i) * step)
        }
        #expect(70 - yf < 70 - ys)
    }

    @Test func nanPassesThroughWithoutResettingTheState() {
        var f = OneEuroFilter(params)
        for i in 0..<10 { _ = f.filter(50, tMs: Double(i) * step) }
        #expect(f.filter(.nan, tMs: 10 * step).isNaN)
        #expect(Swift.abs(f.filter(50, tMs: 11 * step) - 50) < 0.005)
    }

    @Test func nonIncreasingTimestampsStayFinite() {
        var f = OneEuroFilter(params)
        _ = f.filter(1, tMs: 100)
        #expect(f.filter(2, tMs: 100).isFinite)
        #expect(f.filter(3, tMs: 50).isFinite)
    }
}

@Suite("MetricSmoother") struct MetricSmootherTests {
    @Test func smoothsEachMetricIndependently() {
        var smoother = MetricSmoother(names: ["a", "b"], params: params)
        _ = smoother.smooth(["a": 0, "b": 100], tMs: 0)
        let out = smoother.smooth(["a": 10, "b": 100], tMs: step)
        #expect(Swift.abs(out["b"]! - 100) < 0.005)
        #expect(out["a"]! > 0 && out["a"]! < 10)
    }

    @Test func missingInputIsNaN() {
        var smoother = MetricSmoother(names: ["a"], params: params)
        #expect(smoother.smooth([:], tMs: 0)["a"]!.isNaN)
    }
}

/// Scales the horizontal shoulder distance around its midpoint.
private func squeezeShoulders(_ f: Frame, _ k: Double) -> Frame {
    var out = f
    let li = LandmarkName.leftShoulder.index, ri = LandmarkName.rightShoulder.index
    let mid = (out.image[li].x + out.image[ri].x) / 2
    out.image[li].x = mid + (out.image[li].x - mid) * k
    out.image[ri].x = mid + (out.image[ri].x - mid) * k
    return out
}

@Suite("detectView (ref 04 Görünüm)") struct DetectViewTests {
    @Test func frontAndSideSyntheticFrames() {
        #expect(detectView(squatFrame(SquatParams(kneeAngle: 170), FrameOptions(view: .front))) == .front)
        #expect(detectView(squatFrame(SquatParams(kneeAngle: 100, torsoLean: 30), FrameOptions(view: .side))) == .side)
        #expect(detectView(squatFrame(SquatParams(kneeAngle: 100), FrameOptions(view: .front))) == .front)
        #expect(detectView(pushupFrame(PushupParams(elbowAngle: 120), FrameOptions(view: .side))) == .side)
        #expect(detectView(pressFrame(PressParams(elbowAngle: 120), FrameOptions(view: .front))) == .front)
    }

    @Test func inBetweenShoulderWidthIsAmbiguous() {
        #expect(detectView(squeezeShoulders(squatFrame(SquatParams(kneeAngle: 170), FrameOptions(view: .front)), 0.45)) == .ambiguous)
    }

    @Test func thresholdsAreConfigurable() {
        let f = squeezeShoulders(squatFrame(SquatParams(kneeAngle: 170), FrameOptions(view: .front)), 0.45)
        #expect(detectView(f, thresholds: ViewThresholds(front: 0.3, side: 0.2)) == .front)
        #expect(ViewThresholds.default == ViewThresholds(front: 0.45, side: 0.2))
    }
}

@Suite("dominantView") struct DominantViewTests {
    @Test func mostFrequentViewWins() {
        #expect(dominantView([View.front, .front, .side, .ambiguous, .front]) == .front)
        #expect(dominantView([View.side, .ambiguous, .side]) == .side)
    }

    @Test func tiesAndEmptyInputAreAmbiguous() {
        #expect(dominantView([View.front, .side]) == .ambiguous)
        #expect(dominantView([View]()) == .ambiguous)
        #expect(dominantView([View.front, .front, .side, .side, .ambiguous]) == .ambiguous)
    }
}

@Suite("Synthetic generator") struct SyntheticGeneratorTests {
    /// Reference values from the source mulberry32 (`testing/random.ts`),
    /// computed independently with JavaScript's 32-bit integer rules.
    @Test func seededRandomIsBitIdenticalToSource() {
        let expected: [(Int, [Double])] = [
            (1, [0.6270739405881613, 0.002735721180215478, 0.5274470399599522]),
            (7, [0.011704753153026104, 0.06195825757458806, 0.97690763277933]),
            (123_456_789, [0.2577907438389957, 0.9707721115555614, 0.7853280142880976]),
        ]
        for (seed, values) in expected {
            let r = SeededRandom(seed: seed)
            #expect(values.map { _ in r.next() } == values, "seed \(seed)")
        }
    }

    @Test func mirrorFrameSwapsSidesAndFlipsX() {
        let f = squatFrame(SquatParams(kneeAngle: 120, valgus: 0.05), FrameOptions(view: .front))
        let m = mirrorFrame(f)
        #expect(Swift.abs(m[image: .leftKnee].x - (1 - f[image: .rightKnee].x)) < 1e-12)
        #expect(Swift.abs(m[world: .leftKnee].x + f[world: .rightKnee].x) < 1e-12)
        #expect(LandmarkName.mouthLeft.mirrored == .mouthRight)
        #expect(LandmarkName.nose.mirrored == .nose)
        let back = mirrorFrame(m)  // 1 − (1 − x) is x only up to rounding
        for i in 0..<LandmarkName.count {
            #expect(Swift.abs(back.image[i].x - f.image[i].x) < 1e-12 && back.world[i] == f.world[i])
        }
    }

    @Test func timelineHasLeadInRepsRestAndLeadOut() {
        let points = repTimeline(fps: 30, repDurationsMs: [1000, 1000], leadInMs: 500, restMs: 300, leadOutMs: 200)
        #expect(points.first?.t == 0)
        #expect(points.first?.repIndex == nil)
        #expect(points.contains { $0.repIndex == 0 } && points.contains { $0.repIndex == 1 })
        #expect(points.last!.t <= 3000 + 1e-9)
        let peak = points.filter { $0.repIndex == 0 }.map(\.progress).max()!
        #expect(peak > 0.99)
    }

    @Test func sequenceIsReproducibleForASeed() {
        let reps = [squatRep(kneeAngle: 90)]
        let a = squatSequence(view: .front, reps: reps, options: SequenceOptions(noise: 0.003, seed: 7))
        let b = squatSequence(view: .front, reps: reps, options: SequenceOptions(noise: 0.003, seed: 7))
        let c = squatSequence(view: .front, reps: reps, options: SequenceOptions(noise: 0.003, seed: 8))
        #expect(a == b)
        #expect(a != c)
    }
}

@Suite("JavaScript Math semantics") struct JSMathTests {
    @Test func minMaxPropagateNaN() {
        #expect(JSMath.min(1, .nan).isNaN)
        #expect(JSMath.max(.nan, 1).isNaN)
        #expect(JSMath.clampUnit(.nan).isNaN)
        #expect(JSMath.clampUnit(1.5) == 1)
        #expect(JSMath.clampUnit(-1.5) == -1)
    }

    @Test func sign() {
        #expect(JSMath.sign(-3) == -1)
        #expect(JSMath.sign(2) == 1)
        #expect(JSMath.sign(0) == 0)
        #expect(JSMath.sign(-0.0).sign == .minus)
        #expect(JSMath.sign(.nan).isNaN)
    }

    @Test func hypot() {
        #expect(JSMath.hypot(3, 4, 12) == 13)
        #expect(JSMath.hypot(.infinity, .nan, 1) == .infinity)
        #expect(JSMath.hypot(.nan, 1, 1).isNaN)
        #expect(JSMath.hypot(0, 0, 0) == 0)
        #expect(JSMath.hypot(1e300, 1e300, 0).isFinite)
    }
}
