// Rule pack expression language (ref 04 "İfade dili"), translated from the
// source engine (`packages/engine/src/expr`, commit c2fe3fd).
//
// Parsing produces a plain AST; nothing is compiled or executed as code (ref
// AC-4.2). Error reasons and 1-based columns match the source so the one-time
// expression golden (specs/03 AC-3.3) can compare them. Columns count UTF-16
// code units, as JavaScript string indices do.

/// Parse error: reason plus 1-based column in the source expression.
public struct ExpressionError: Error, Equatable, Sendable, CustomStringConvertible {
    public let reason: String
    public let column: Int

    public init(_ reason: String, column: Int) {
        self.reason = reason
        self.column = column
    }

    /// Same text as the source `ExpressionError.message`.
    public var description: String { "\(reason) (column \(column))" }
}

public enum CompareOp: String, Sendable, Equatable {
    case greater = ">"
    case less = "<"
    case greaterOrEqual = ">="
    case lessOrEqual = "<="
}

public enum ExpressionFunction: String, CaseIterable, Sendable, Equatable {
    case abs, avg, min, max
}

public indirect enum ValueNode: Sendable, Equatable {
    case number(Double)
    case metric(String)
    case call(ExpressionFunction, [ValueNode])
}

public indirect enum Expr: Sendable, Equatable {
    case or(Expr, Expr)
    case and(Expr, Expr)
    case not(Expr)
    case compare(CompareOp, ValueNode, ValueNode)
}

/// Fault check positions (ref 04 "Hata konumu"). `sequence:` is v1.0 (specs/04).
public enum CheckPosition: String, CaseIterable, Sendable, Equatable {
    case atTurn = "at_turn"
    case atStart = "at_start"
    case duringRep = "during_rep"
}

// MARK: - Tokens

enum Token: Equatable {
    case number(value: Double, raw: String, column: Int)
    case ident(String, column: Int)
    case op(CompareOp, column: Int)
    case lparen(column: Int)
    case rparen(column: Int)
    case comma(column: Int)
    case colon(column: Int)
    case eof(column: Int)

    var column: Int {
        switch self {
        case .number(_, _, let c), .ident(_, let c), .op(_, let c), .lparen(let c), .rparen(let c),
             .comma(let c), .colon(let c), .eof(let c):
            c
        }
    }
}

enum Tokenizer {
    /// Splits an expression into tokens. Anything outside the grammar (quotes,
    /// '=', '.', '[', uppercase, …) is a hard error.
    static func tokenize(_ src: String) throws(ExpressionError) -> [Token] {
        let u = Array(src.utf16)
        var tokens: [Token] = []
        var i = 0
        func isDigit(_ c: UInt16) -> Bool { c >= 0x30 && c <= 0x39 }
        func isIdentStart(_ c: UInt16) -> Bool { (c >= 0x61 && c <= 0x7A) || c == 0x5F }
        func isIdentPart(_ c: UInt16) -> Bool { isIdentStart(c) || isDigit(c) }

        while i < u.count {
            let ch = u[i]
            let column = i + 1
            if ch == 0x20 || ch == 0x09 {
                i += 1
                continue
            }
            // NUMBER = /^-?\d+(?:\.\d+)?/
            var j = i
            if u[j] == 0x2D { j += 1 }
            if j < u.count, isDigit(u[j]) {
                while j < u.count, isDigit(u[j]) { j += 1 }
                if j + 1 < u.count, u[j] == 0x2E, isDigit(u[j + 1]) {
                    j += 1
                    while j < u.count, isDigit(u[j]) { j += 1 }
                }
                let raw = String(decoding: u[i..<j], as: UTF16.self)
                tokens.append(.number(value: Double(raw)!, raw: raw, column: column))
                i = j
                continue
            }
            // IDENT = /^[a-z_][a-z0-9_]*/
            if isIdentStart(ch) {
                var k = i + 1
                while k < u.count, isIdentPart(u[k]) { k += 1 }
                tokens.append(.ident(String(decoding: u[i..<k], as: UTF16.self), column: column))
                i = k
                continue
            }
            if ch == 0x3E || ch == 0x3C {  // '>' '<'
                let orEqual = i + 1 < u.count && u[i + 1] == 0x3D
                let op: CompareOp = ch == 0x3E
                    ? (orEqual ? .greaterOrEqual : .greater)
                    : (orEqual ? .lessOrEqual : .less)
                tokens.append(.op(op, column: column))
                i += orEqual ? 2 : 1
                continue
            }
            switch ch {
            case 0x28: tokens.append(.lparen(column: column))
            case 0x29: tokens.append(.rparen(column: column))
            case 0x2C: tokens.append(.comma(column: column))
            case 0x3A: tokens.append(.colon(column: column))
            default:
                throw ExpressionError("unexpected character '\(Self.character(at: i, in: u))'", column: column)
            }
            i += 1
        }
        tokens.append(.eof(column: u.count + 1))
        return tokens
    }

    /// The UTF-16 code unit at `i` as text (`src[i]` in JavaScript).
    private static func character(at i: Int, in u: [UInt16]) -> String {
        if let scalar = Unicode.Scalar(UInt32(u[i])) { return String(Character(scalar)) }
        // Half of a surrogate pair: show the full character when possible.
        if i + 1 < u.count, UTF16.isLeadSurrogate(u[i]) {
            return String(decoding: u[i...i + 1], as: UTF16.self)
        }
        return "\u{FFFD}"
    }
}

// MARK: - Parser

public enum ExpressionParser {
    static let keywords: Set<String> = ["and", "or", "not", "for", "ms"]

    /// - Parameter metrics: defined metric names; when given, references to
    ///   anything else are errors.
    public static func parseExpression(_ src: String, metrics: Set<String>? = nil) throws(ExpressionError) -> Expr {
        var p = Parser(tokens: try Tokenizer.tokenize(src), metrics: metrics)
        let expr = try p.expr()
        try p.expectEnd()
        return expr
    }

    public static func parseCheck(
        _ src: String, metrics: Set<String>? = nil
    ) throws(ExpressionError) -> (position: CheckPosition, expr: Expr) {
        var p = Parser(tokens: try Tokenizer.tokenize(src), metrics: metrics)
        let head = p.next()
        guard case .ident(let name, _) = head, let position = CheckPosition(rawValue: name) else {
            let names = CheckPosition.allCases.map(\.rawValue).joined(separator: ", ")
            throw ExpressionError("check must start with one of \(names)", column: head.column)
        }
        try p.expectColon()
        let expr = try p.expr()
        try p.expectEnd()
        return (position, expr)
    }

    public static func parseReadyPose(
        _ src: String, metrics: Set<String>? = nil
    ) throws(ExpressionError) -> (expr: Expr, durationMs: Int) {
        var p = Parser(tokens: try Tokenizer.tokenize(src), metrics: metrics)
        let expr = try p.expr()
        try p.expectKeyword("for")
        let n = p.next()
        guard case .number(let value, let raw, _) = n,
              raw.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }), value > 0,
              let duration = Int(exactly: value)
        else {
            throw ExpressionError("expected a positive integer duration", column: n.column)
        }
        try p.expectKeyword("ms")
        try p.expectEnd()
        return (expr, duration)
    }
}

private struct Parser {
    let tokens: [Token]
    let metrics: Set<String>?
    var i = 0

    func peek() -> Token { tokens[i] }

    mutating func next() -> Token {
        let t = tokens[i]
        if case .eof = t {} else { i += 1 }
        return t
    }

    mutating func expectColon() throws(ExpressionError) {
        let t = next()
        guard case .colon = t else { throw ExpressionError("expected ':' after check position", column: t.column) }
    }

    mutating func expectRParen() throws(ExpressionError) {
        let t = next()
        guard case .rparen = t else { throw ExpressionError("expected ')'", column: t.column) }
    }

    mutating func expectKeyword(_ word: String) throws(ExpressionError) {
        let t = next()
        guard case .ident(let name, _) = t, name == word else {
            throw ExpressionError("expected '\(word)'", column: t.column)
        }
    }

    func expectEnd() throws(ExpressionError) {
        let t = peek()
        if case .op = t { throw ExpressionError("comparisons cannot be chained", column: t.column) }
        if case .eof = t { return }
        throw ExpressionError("unexpected input", column: t.column)
    }

    func isKeyword(_ word: String) -> Bool {
        if case .ident(let name, _) = peek() { return name == word }
        return false
    }

    // expr = and_expr { "or" and_expr }
    mutating func expr() throws(ExpressionError) -> Expr {
        var left = try and()
        while isKeyword("or") {
            _ = next()
            left = .or(left, try and())
        }
        return left
    }

    // and_expr = not_expr { "and" not_expr }
    mutating func and() throws(ExpressionError) -> Expr {
        var left = try not()
        while isKeyword("and") {
            _ = next()
            left = .and(left, try not())
        }
        return left
    }

    // not_expr = "not" not_expr | "(" expr ")" | compare
    mutating func not() throws(ExpressionError) -> Expr {
        if isKeyword("not") {
            _ = next()
            return .not(try not())
        }
        if case .lparen = peek() {
            _ = next()
            let inner = try expr()
            try expectRParen()
            return inner
        }
        return try compare()
    }

    // compare = value op value
    mutating func compare() throws(ExpressionError) -> Expr {
        let left = try value()
        let t = next()
        guard case .op(let op, _) = t else {
            throw ExpressionError("expected a comparison operator", column: t.column)
        }
        return .compare(op, left, try value())
    }

    // value = NUMBER | METRIC | func "(" value { "," value } ")"
    mutating func value() throws(ExpressionError) -> ValueNode {
        let t = next()
        if case .number(let v, _, _) = t { return .number(v) }
        guard case .ident(let name, let column) = t else {
            throw ExpressionError("expected a number, metric or function", column: t.column)
        }
        if ExpressionParser.keywords.contains(name) {
            throw ExpressionError("unexpected keyword '\(name)'", column: column)
        }
        if case .lparen = peek() {
            guard let fn = ExpressionFunction(rawValue: name) else {
                throw ExpressionError("unknown function '\(name)'", column: column)
            }
            _ = next()
            var args = [try value()]
            while case .comma = peek() {
                _ = next()
                args.append(try value())
            }
            try expectRParen()
            if fn == .abs, args.count != 1 {
                throw ExpressionError("abs takes exactly 1 argument", column: column)
            }
            return .call(fn, args)
        }
        if let metrics, !metrics.contains(name) {
            throw ExpressionError("unknown metric '\(name)'", column: column)
        }
        return .metric(name)
    }
}

// MARK: - Evaluation

/// Three-valued (Kleene) evaluation: a missing or NaN metric makes its
/// comparison unknown (`nil`). Callers treat unknown as "condition not met",
/// so uncertain data never raises a fault (ref 04 "Bilinmeyen değer").
extension Expr {
    public func evaluate(_ values: [String: Double]) -> Bool? {
        switch self {
        case .compare(let op, let leftNode, let rightNode):
            let l = leftNode.value(values)
            let r = rightNode.value(values)
            if l.isNaN || r.isNaN { return nil }
            switch op {
            case .greater: return l > r
            case .less: return l < r
            case .greaterOrEqual: return l >= r
            case .lessOrEqual: return l <= r
            }
        case .not(let operand):
            return operand.evaluate(values).map { !$0 }
        case .and(let leftExpr, let rightExpr):
            let l = leftExpr.evaluate(values)
            if l == false { return false }
            let r = rightExpr.evaluate(values)
            if r == false { return false }
            return l == nil || r == nil ? nil : true
        case .or(let leftExpr, let rightExpr):
            let l = leftExpr.evaluate(values)
            if l == true { return true }
            let r = rightExpr.evaluate(values)
            if r == true { return true }
            return l == nil || r == nil ? nil : false
        }
    }

    /// Metric names referenced by the expression.
    public var metricNames: Set<String> {
        switch self {
        case .compare(_, let l, let r): l.metricNames.union(r.metricNames)
        case .not(let e): e.metricNames
        case .and(let l, let r), .or(let l, let r): l.metricNames.union(r.metricNames)
        }
    }
}

extension ValueNode {
    func value(_ values: [String: Double]) -> Double {
        switch self {
        case .number(let v):
            return v
        case .metric(let name):
            return values[name] ?? .nan
        case .call(let fn, let nodes):
            let args = nodes.map { $0.value(values) }
            switch fn {
            case .abs:
                return Swift.abs(args[0])
            case .avg:
                return args.reduce(0, +) / Double(args.count)
            case .min:
                // Math.min: any NaN argument gives NaN.
                return args.contains(where: \.isNaN) ? .nan : args.min()!
            case .max:
                return args.contains(where: \.isNaN) ? .nan : args.max()!
            }
        }
    }

    var metricNames: Set<String> {
        switch self {
        case .number: []
        case .metric(let name): [name]
        case .call(_, let args): args.reduce(into: Set<String>()) { $0.formUnion($1.metricNames) }
        }
    }
}
