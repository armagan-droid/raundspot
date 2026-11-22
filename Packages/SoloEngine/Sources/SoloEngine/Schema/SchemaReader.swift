/// A validation issue: "path: message", like the source's Zod issues.
public struct SchemaIssue: Sendable, Equatable, CustomStringConvertible {
    public enum Code: String, Sendable, Equatable {
        /// Shape, type or cross-field rule violation.
        case schema
        /// Expression parse error (fault check, readyPose).
        case expression
        /// The template uses a landmark the skeleton lacks (specs/03 AC-3.5).
        case unsupportedLandmark = "unsupported_landmark"
        /// The template uses a world (3D) metric while 3D is off (specs/03).
        case worldUnavailable = "world_unavailable"
    }

    public var path: String
    public var message: String
    public var code: Code

    public init(path: String, message: String, code: Code = .schema) {
        self.path = path
        self.message = message
        self.code = code
    }

    public var description: String { "\(path): \(message)" }
}

/// Strict JSON reader that collects issues instead of stopping at the first one.
struct SchemaReader {
    private(set) var issues: [SchemaIssue] = []

    mutating func add(_ path: [String], _ message: String, code: SchemaIssue.Code = .schema) {
        issues.append(SchemaIssue(path: path.joined(separator: "."), message: message, code: code))
    }

    private mutating func typeMismatch(_ path: [String], expected: String, got value: JSONValue?) {
        add(path, "Invalid input: expected \(expected), received \(value?.typeName ?? "undefined")")
    }

    /// Strict object: unknown keys are issues (Zod `strictObject`).
    mutating func object(_ value: JSONValue?, _ path: [String], keys: [String]) -> JSONObject? {
        guard let object = value?.objectValue else {
            typeMismatch(path, expected: "object", got: value)
            return nil
        }
        let unknown = object.keys.filter { !keys.contains($0) }
        if !unknown.isEmpty {
            let list = unknown.map { "\"\($0)\"" }.joined(separator: ", ")
            add(path, unknown.count == 1 ? "Unrecognized key: \(list)" : "Unrecognized keys: \(list)")
        }
        return object
    }

    mutating func string(_ value: JSONValue?, _ path: [String]) -> String? {
        guard let s = value?.stringValue else {
            typeMismatch(path, expected: "string", got: value)
            return nil
        }
        return s
    }

    mutating func nonEmptyString(_ value: JSONValue?, _ path: [String]) -> String? {
        guard let s = string(value, path) else { return nil }
        if s.isEmpty {
            add(path, "Too small: expected string to have >=1 characters")
            return nil
        }
        return s
    }

    /// snake_case starting with a letter (source `IdentifierSchema`).
    mutating func identifier(_ value: JSONValue?, _ path: [String]) -> String? {
        guard let s = string(value, path) else { return nil }
        guard Self.isIdentifier(s) else {
            add(path, "must be snake_case starting with a letter")
            return nil
        }
        return s
    }

    static func isIdentifier(_ s: String) -> Bool {
        let u = Array(s.utf8)
        guard let first = u.first, first >= 0x61, first <= 0x7A else { return false }
        return u.allSatisfy { ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x5F }
    }

    mutating func number(_ value: JSONValue?, _ path: [String]) -> Double? {
        guard let n = value?.numberValue else {
            typeMismatch(path, expected: "number", got: value)
            return nil
        }
        guard n.isFinite else {
            add(path, "Invalid input: expected number, received number")
            return nil
        }
        return n
    }

    mutating func number(_ value: JSONValue?, _ path: [String], where check: (Double) -> Bool, _ message: String) -> Double? {
        guard let n = number(value, path) else { return nil }
        guard check(n) else {
            add(path, message)
            return nil
        }
        return n
    }

    /// Safe integer (Zod `z.int()`), optionally bounded below.
    mutating func int(_ value: JSONValue?, _ path: [String], min: Int? = nil) -> Int? {
        guard let n = number(value, path) else { return nil }
        guard n.rounded() == n, Swift.abs(n) <= 9_007_199_254_740_991 else {
            add(path, "Invalid input: expected int, received number")
            return nil
        }
        let i = Int(n)
        if let min, i < min {
            add(path, "Too small: expected number to be >=\(min)")
            return nil
        }
        return i
    }

    mutating func bool(_ value: JSONValue?, _ path: [String]) -> Bool? {
        guard let b = value?.boolValue else {
            typeMismatch(path, expected: "boolean", got: value)
            return nil
        }
        return b
    }

    mutating func enumValue<E: RawRepresentable>(_ value: JSONValue?, _ path: [String], _: E.Type, options: [String]) -> E?
    where E.RawValue == String {
        guard let s = string(value, path) else { return nil }
        guard let e = E(rawValue: s), options.contains(s) else {
            add(path, "Invalid option: expected one of \(options.map { "\"\($0)\"" }.joined(separator: "|"))")
            return nil
        }
        return e
    }

    mutating func array(_ value: JSONValue?, _ path: [String], minCount: Int = 0, maxCount: Int? = nil) -> [JSONValue]? {
        guard let a = value?.arrayValue else {
            typeMismatch(path, expected: "array", got: value)
            return nil
        }
        if a.count < minCount {
            add(path, "Too small: expected array to have >=\(minCount) items")
            return nil
        }
        if let maxCount, a.count > maxCount {
            add(path, "Too big: expected array to have <=\(maxCount) items")
            return nil
        }
        return a
    }

    /// Each element must parse; returns nil if any element fails.
    mutating func elements<T>(_ values: [JSONValue], _ path: [String], _ parse: (inout SchemaReader, JSONValue, [String]) -> T?) -> [T]? {
        var out: [T] = []
        var ok = true
        for (i, v) in values.enumerated() {
            if let t = parse(&self, v, path + ["\(i)"]) { out.append(t) } else { ok = false }
        }
        return ok ? out : nil
    }

    mutating func localizedText(_ value: JSONValue?, _ path: [String]) -> LocalizedText? {
        guard let o = object(value, path, keys: ["tr", "en"]) else { return nil }
        let tr = nonEmptyString(o["tr"], path + ["tr"])
        let en = nonEmptyString(o["en"], path + ["en"])
        guard let tr, let en else { return nil }
        return LocalizedText(tr: tr, en: en)
    }

    mutating func landmarkRef(_ value: JSONValue?, _ path: [String]) -> LandmarkRef? {
        guard let s = string(value, path) else { return nil }
        guard let ref = LandmarkRef(s) else {
            add(path, "Invalid option: '\(s)' is not a landmark")
            return nil
        }
        return ref
    }
}

// MARK: - JavaScript regular expression semantics

/// Character classes as JavaScript regular expressions define them (no `u`
/// flag, UTF-16 code units). Swift `Regex` and ICU treat `\s`, `\d` and `.`
/// differently, so the source patterns are matched by hand.
enum JSRegex {
    /// `\s`
    static func isWhitespace(_ c: UInt16) -> Bool {
        switch c {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
            true
        default:
            false
        }
    }

    /// Characters `.` does not match.
    static func isLineTerminator(_ c: UInt16) -> Bool {
        c == 0x0A || c == 0x0D || c == 0x2028 || c == 0x2029
    }

    static func isDigit(_ c: UInt16) -> Bool { c >= 0x30 && c <= 0x39 }

    /// `^(at_turn|at_start|during_rep):\s*\S`
    static func matchesCheck(_ s: String) -> Bool {
        let u = Array(s.utf16)
        for position in CheckPosition.allCases {
            let prefix = Array((position.rawValue + ":").utf16)
            guard u.starts(with: prefix) else { continue }
            var i = prefix.count
            while i < u.count, isWhitespace(u[i]) { i += 1 }
            return i < u.count
        }
        return false
    }

    /// `^\S.*\sfor\s+\d+ms$`
    ///
    /// `\s+` must sit directly between "for" and the digits, and the digits
    /// directly before "ms", so both runs are maximal and the match is unique.
    static func matchesReadyPose(_ s: String) -> Bool {
        let u = Array(s.utf16)
        guard u.count >= 2, u[u.count - 2] == 0x6D, u[u.count - 1] == 0x73 else { return false }  // "ms"
        var k = u.count - 2
        while k > 0, isDigit(u[k - 1]) { k -= 1 }
        guard k < u.count - 2 else { return false }  // \d+
        var a = k
        while a > 0, isWhitespace(u[a - 1]) { a -= 1 }
        guard a < k else { return false }  // \s+
        guard a >= 3, u[a - 3] == 0x66, u[a - 2] == 0x6F, u[a - 1] == 0x72 else { return false }  // "for"
        let space = a - 4  // \s before "for"
        guard space >= 1, isWhitespace(u[space]) else { return false }
        guard !isWhitespace(u[0]) else { return false }  // ^\S
        return u[1..<space].allSatisfy { !isLineTerminator($0) }  // .*
    }
}
