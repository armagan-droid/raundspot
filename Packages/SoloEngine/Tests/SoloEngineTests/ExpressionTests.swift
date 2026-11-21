import Testing
@testable import SoloEngine

// Port of the source `engine/test/expr.test.ts` (commit c2fe3fd).

private let metrics: Set<String> = ["knee_angle_avg", "torso_lean", "knee_valgus_l", "knee_valgus_r", "hip_offset"]
private func parse(_ src: String) throws -> Expr { try ExpressionParser.parseExpression(src, metrics: metrics) }
private func fails(_ src: String) -> Bool { (try? parse(src)) == nil }

@Suite("Expression AST") struct ExpressionASTTests {
    @Test func comparisonOfMetricAndNumber() throws {
        #expect(try parse("knee_angle_avg > 160") == .compare(.greater, .metric("knee_angle_avg"), .number(160)))
    }

    @Test func negativeAndDecimalNumbers() throws {
        #expect(try parse("hip_offset < -0.06") == .compare(.less, .metric("hip_offset"), .number(-0.06)))
    }

    @Test(arguments: [(">", CompareOp.greater), ("<", .less), (">=", .greaterOrEqual), ("<=", .lessOrEqual)])
    func allComparisonOperators(_ src: String, _ op: CompareOp) throws {
        #expect(try parse("torso_lean \(src) 1") == .compare(op, .metric("torso_lean"), .number(1)))
    }

    @Test func andBindsTighterThanOr() throws {
        guard case .or(.compare, .and) = try parse("torso_lean > 1 or torso_lean > 2 and torso_lean > 3") else {
            Issue.record("wrong precedence"); return
        }
    }

    @Test func notBindsTighterThanAnd() throws {
        guard case .and(.not(.compare), _) = try parse("not torso_lean > 1 and torso_lean > 2") else {
            Issue.record("wrong precedence"); return
        }
    }

    @Test func parenthesesOverridePrecedence() throws {
        guard case .and(.or, _) = try parse("(torso_lean > 1 or torso_lean > 2) and torso_lean > 3") else {
            Issue.record("wrong precedence"); return
        }
    }

    @Test func functionCalls() throws {
        #expect(try parse("abs(hip_offset) > 0.1") == .compare(.greater, .call(.abs, [.metric("hip_offset")]), .number(0.1)))
        #expect(try parse("max(knee_valgus_l, knee_valgus_r) > 0.15")
            == .compare(.greater, .call(.max, [.metric("knee_valgus_l"), .metric("knee_valgus_r")]), .number(0.15)))
        #expect(try parse("avg(min(torso_lean, 3), 4) < 5")
            == .compare(.less, .call(.avg, [.call(.min, [.metric("torso_lean"), .number(3)]), .number(4)]), .number(5)))
    }

    @Test func whitespaceIsInsignificant() throws {
        #expect(try parse("  torso_lean>=1and(not torso_lean<2)") == parse("torso_lean >= 1 and (not torso_lean < 2)"))
    }
}

@Suite("Check and readyPose forms") struct CheckFormTests {
    @Test func parseCheckSplitsPositionAndExpression() throws {
        let c = try ExpressionParser.parseCheck("at_turn: knee_angle_avg > 100", metrics: metrics)
        #expect(c.position == .atTurn)
        #expect(try c.expr == parse("knee_angle_avg > 100"))
        #expect(try ExpressionParser.parseCheck("during_rep: torso_lean > 1", metrics: metrics).position == .duringRep)
        #expect(try ExpressionParser.parseCheck("at_start: torso_lean > 1", metrics: metrics).position == .atStart)
    }

    @Test func parseCheckRejectsUnknownPositionsAndMissingColon() {
        #expect(throws: ExpressionError.self) { try ExpressionParser.parseCheck("at_phase_bottom: torso_lean > 1", metrics: metrics) }
        #expect(throws: ExpressionError.self) { try ExpressionParser.parseCheck("torso_lean > 1", metrics: metrics) }
    }

    @Test func parseReadyPoseExtractsDuration() throws {
        let r = try ExpressionParser.parseReadyPose("knee_angle_avg > 165 for 1500ms", metrics: metrics)
        #expect(r.durationMs == 1500)
        #expect(try r.expr == parse("knee_angle_avg > 165"))
    }

    @Test(arguments: ["knee_angle_avg > 165", "knee_angle_avg > 165 for 1.5ms", "knee_angle_avg > 165 for 1500",
                      "knee_angle_avg > 165 for -5ms"])
    func parseReadyPoseRequiresIntegerMsDuration(_ bad: String) {
        #expect(throws: ExpressionError.self) { try ExpressionParser.parseReadyPose(bad, metrics: metrics) }
    }

    @Test func forIsNotAllowedInsidePlainExpressions() {
        #expect(fails("knee_angle_avg > 165 for 1500ms"))
    }
}

@Suite("AC-4.2: bad input is rejected and never executed") struct MaliciousInputTests {
    static let malicious = [
        "eval(\"1\")", "eval(1) > 0", "Function('return 1')() > 0", "process.exit(1)",
        "torso_lean > 1; process.exit(1)", "constructor > 0", "__proto__ > 0", "torso_lean.constructor > 0",
        "torso_lean['x'] > 0", "`x` > 0", "\"1\" > 0", "torso_lean == 1", "torso_lean = 1", "torso_lean != 1",
        "!(torso_lean > 1)", "torso_lean > 1 && torso_lean < 2", "() => 1", "TORSO_LEAN > 1",
    ]

    @Test(arguments: malicious) func rejects(_ src: String) {
        #expect(fails(src))
    }

    @Test func unknownMetricIsRejectedWithItsName() {
        #expect(throws: ExpressionError("unknown metric 'hip_angle'", column: 1)) { try parse("hip_angle > 1") }
    }

    @Test func unknownFunctionIsRejected() {
        #expect(throws: ExpressionError("unknown function 'sqrt'", column: 1)) { try parse("sqrt(torso_lean) > 1") }
    }

    @Test(arguments: [
        "", "torso_lean", "torso_lean >", "> 1", "torso_lean > 1 >", "torso_lean < 1 < 2", "(torso_lean > 1",
        "torso_lean > 1)", "torso_lean > 1 and", "abs() > 1", "abs(torso_lean, hip_offset) > 1",
        "avg(torso_lean,) > 1", "1.5.2 > 1", "- 1 > torso_lean",
    ])
    func structuralErrors(_ bad: String) {
        #expect(fails(bad))
    }

    @Test func errorsReportTheColumn() {
        #expect(throws: ExpressionError("unexpected character '&'", column: 16)) { try parse("torso_lean > 1 & 2") }
    }

    @Test func withoutMetricSetAnySnakeCaseIdentifierIsAccepted() throws {
        #expect(try ExpressionParser.parseExpression("anything_goes > 1") == .compare(.greater, .metric("anything_goes"), .number(1)))
    }

    /// Same reason text and column as the source for representative errors.
    @Test func messagesMatchSource() {
        let cases: [(String, String)] = [
            ("", "expected a number, metric or function (column 1)"),
            ("torso_lean", "expected a comparison operator (column 11)"),
            ("torso_lean < 1 < 2", "comparisons cannot be chained (column 16)"),
            ("torso_lean > 1)", "unexpected input (column 15)"),
            ("(torso_lean > 1", "expected ')' (column 16)"),
            ("abs(torso_lean, hip_offset) > 1", "abs takes exactly 1 argument (column 1)"),
            ("torso_lean > and", "unexpected keyword 'and' (column 14)"),
            ("ş > 1", "unexpected character 'ş' (column 1)"),
        ]
        for (src, message) in cases {
            do {
                _ = try ExpressionParser.parseExpression(src, metrics: metrics)
                Issue.record("expected failure for \(src)")
            } catch {
                #expect(error.description == message, "\(src)")
            }
        }
    }

    /// Tokenizing stops at the first character outside the grammar, so only
    /// that character can be non-ASCII; it is reported whole even when it is
    /// a surrogate pair in UTF-16.
    @Test func nonASCIICharacterIsReportedWhole() {
        #expect(throws: ExpressionError("unexpected character '😀'", column: 14)) { try parse("torso_lean > 😀") }
        #expect(throws: ExpressionError("unknown metric 'x'", column: 19)) {
            try ExpressionParser.parseCheck("at_turn: 1 > 2 or x > 1", metrics: metrics)
        }
    }
}

@Suite("Expression evaluation") struct EvaluateTests {
    private func ev(_ src: String, _ values: [String: Double]) throws -> Bool? { try parse(src).evaluate(values) }

    @Test func comparisons() throws {
        #expect(try ev("torso_lean > 10", ["torso_lean": 11]) == true)
        #expect(try ev("torso_lean > 10", ["torso_lean": 10]) == false)
        #expect(try ev("torso_lean >= 10", ["torso_lean": 10]) == true)
        #expect(try ev("torso_lean < 10", ["torso_lean": 9]) == true)
        #expect(try ev("torso_lean <= 10", ["torso_lean": 10]) == true)
    }

    @Test func booleanOperators() throws {
        #expect(try ev("torso_lean > 1 and hip_offset > 1", ["torso_lean": 2, "hip_offset": 0]) == false)
        #expect(try ev("torso_lean > 1 or hip_offset > 1", ["torso_lean": 2, "hip_offset": 0]) == true)
        #expect(try ev("not torso_lean > 1", ["torso_lean": 2]) == false)
    }

    @Test func functions() throws {
        #expect(try ev("abs(hip_offset) > 0.05", ["hip_offset": -0.06]) == true)
        #expect(try ev("avg(knee_valgus_l, knee_valgus_r) > 0.1", ["knee_valgus_l": 0.05, "knee_valgus_r": 0.2]) == true)
        #expect(try ev("min(knee_valgus_l, knee_valgus_r) > 0.1", ["knee_valgus_l": 0.05, "knee_valgus_r": 0.2]) == false)
        #expect(try ev("max(knee_valgus_l, knee_valgus_r) > 0.1", ["knee_valgus_l": 0.05, "knee_valgus_r": 0.2]) == true)
    }

    @Test func missingOrNaNMetricMakesComparisonUnknown() throws {
        #expect(try ev("torso_lean > 1", [:]) == nil)
        #expect(try ev("torso_lean > 1", ["torso_lean": .nan]) == nil)
    }

    @Test func notOfUnknownStaysUnknown() throws {
        #expect(try ev("not torso_lean > 1", ["torso_lean": .nan]) == nil)
    }

    @Test func andOrFollowKleeneLogic() throws {
        #expect(try ev("torso_lean > 1 and hip_offset > 1", ["torso_lean": 0]) == false)
        #expect(try ev("torso_lean > 1 and hip_offset > 1", ["torso_lean": 2]) == nil)
        #expect(try ev("torso_lean > 1 or hip_offset > 1", ["torso_lean": 2]) == true)
        #expect(try ev("torso_lean > 1 or hip_offset > 1", ["torso_lean": 0]) == nil)
    }

    @Test func functionsPropagateUnknown() throws {
        #expect(try ev("max(knee_valgus_l, knee_valgus_r) > 0.1", ["knee_valgus_l": 0.5]) == nil)
        // Math.min/Math.max: NaN in any position gives NaN (Swift.min would not).
        #expect(try ev("min(knee_valgus_l, knee_valgus_r) < 1", ["knee_valgus_l": .nan, "knee_valgus_r": 0.5]) == nil)
        #expect(try ev("min(knee_valgus_l, knee_valgus_r) < 1", ["knee_valgus_l": 0.5, "knee_valgus_r": .nan]) == nil)
    }

    @Test func prototypePropertiesAreNotMetricValues() throws {
        #expect(try ExpressionParser.parseExpression("constructor > 0").evaluate([:]) == nil)
    }

    @Test func metricNamesAreCollected() throws {
        #expect(try parse("abs(hip_offset) > 1 or not max(knee_valgus_l, 2) < torso_lean").metricNames
            == ["hip_offset", "knee_valgus_l", "torso_lean"])
    }
}
