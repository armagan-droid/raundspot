import Foundation

/// A JSON value that keeps object key order.
///
/// The source engine validates `JSON.parse` output, whose objects iterate in
/// insertion order; metric order decides cycle reports and issue order. Swift
/// dictionaries do not keep order, so rule packs and sequences are read with
/// this small strict RFC 8259 parser instead of `JSONSerialization`.
public enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object(JSONObject)

    /// JSON type name used in validation messages.
    public var typeName: String {
        switch self {
        case .null: "null"
        case .bool: "boolean"
        case .number: "number"
        case .string: "string"
        case .array: "array"
        case .object: "object"
        }
    }

    public var objectValue: JSONObject? { if case .object(let o) = self { o } else { nil } }
    public var arrayValue: [JSONValue]? { if case .array(let a) = self { a } else { nil } }
    public var stringValue: String? { if case .string(let s) = self { s } else { nil } }
    public var numberValue: Double? { if case .number(let n) = self { n } else { nil } }
    public var boolValue: Bool? { if case .bool(let b) = self { b } else { nil } }
    public var isNull: Bool { self == .null }
}

/// JSON object with insertion-ordered keys. A duplicate key keeps the position
/// of its first occurrence and the value of its last (as `JSON.parse`).
public struct JSONObject: Sendable, Equatable {
    public private(set) var keys: [String] = []
    private var storage: [String: JSONValue] = [:]

    public init() {}

    public init(_ pairs: [(String, JSONValue)]) {
        for (key, value) in pairs { self[key] = value }
    }

    public subscript(key: String) -> JSONValue? {
        get { storage[key] }
        set {
            if let newValue {
                if storage.updateValue(newValue, forKey: key) == nil { keys.append(key) }
            } else if storage.removeValue(forKey: key) != nil {
                keys.removeAll { $0 == key }
            }
        }
    }

    public var entries: [(key: String, value: JSONValue)] { keys.map { ($0, storage[$0]!) } }
    public var count: Int { keys.count }

    public static func == (lhs: JSONObject, rhs: JSONObject) -> Bool {
        lhs.keys == rhs.keys && lhs.storage == rhs.storage
    }
}

// MARK: - Mutation helpers (tests and tools edit parsed documents)

extension JSONValue {
    public subscript(key: String) -> JSONValue? {
        get { objectValue?[key] }
        set {
            guard case .object(var object) = self else { return }
            object[key] = newValue
            self = .object(object)
        }
    }

    public subscript(index: Int) -> JSONValue? {
        get {
            guard let array = arrayValue, array.indices.contains(index) else { return nil }
            return array[index]
        }
        set {
            guard case .array(var array) = self, array.indices.contains(index) else { return }
            if let newValue { array[index] = newValue } else { array.remove(at: index) }
            self = .array(array)
        }
    }

    /// Appends to an array value; no-op otherwise.
    public mutating func append(_ value: JSONValue) {
        guard case .array(var array) = self else { return }
        array.append(value)
        self = .array(array)
    }
}

extension JSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByStringLiteral, ExpressibleByArrayLiteral,
    ExpressibleByDictionaryLiteral {
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) { self = .object(JSONObject(elements)) }
}

// MARK: - Parsing

public struct JSONParseError: Error, Equatable, CustomStringConvertible, Sendable {
    public let message: String
    /// Byte offset into the UTF-8 input.
    public let offset: Int

    public var description: String { "invalid JSON at byte \(offset): \(message)" }
}

extension JSONValue {
    public static func parse(_ data: Data) throws(JSONParseError) -> JSONValue {
        guard String(data: data, encoding: .utf8) != nil else {
            throw JSONParseError(message: "input is not valid UTF-8", offset: 0)
        }
        var parser = JSONParser(bytes: [UInt8](data))
        return try parser.parseDocument()
    }

    public static func parse(_ text: String) throws(JSONParseError) -> JSONValue {
        try parse(Data(text.utf8))
    }

    public static func parse(contentsOf url: URL) throws -> JSONValue {
        try parse(try Data(contentsOf: url))
    }
}

private struct JSONParser {
    let bytes: [UInt8]
    var i = 0
    var depth = 0
    static let maxDepth = 512

    init(bytes: [UInt8]) { self.bytes = bytes }

    func fail(_ message: String) -> JSONParseError { JSONParseError(message: message, offset: i) }

    mutating func parseDocument() throws(JSONParseError) -> JSONValue {
        skipWhitespace()
        let value = try parseValue()
        skipWhitespace()
        guard i == bytes.count else { throw fail("unexpected data after the top-level value") }
        return value
    }

    mutating func skipWhitespace() {
        while i < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) { i += 1 }
    }

    mutating func parseValue() throws(JSONParseError) -> JSONValue {
        guard i < bytes.count else { throw fail("unexpected end of input") }
        switch bytes[i] {
        case UInt8(ascii: "{"): return try parseObject()
        case UInt8(ascii: "["): return try parseArray()
        case UInt8(ascii: "\""): return .string(try parseString())
        case UInt8(ascii: "t"): try literal("true"); return .bool(true)
        case UInt8(ascii: "f"): try literal("false"); return .bool(false)
        case UInt8(ascii: "n"): try literal("null"); return .null
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return .number(try parseNumber())
        default: throw fail("unexpected character")
        }
    }

    mutating func literal(_ word: String) throws(JSONParseError) {
        let w = Array(word.utf8)
        guard i + w.count <= bytes.count, Array(bytes[i..<i + w.count]) == w else {
            throw fail("invalid literal")
        }
        i += w.count
    }

    mutating func enter() throws(JSONParseError) {
        depth += 1
        if depth > Self.maxDepth { throw fail("nesting too deep") }
    }

    mutating func parseObject() throws(JSONParseError) -> JSONValue {
        try enter()
        i += 1
        var object = JSONObject()
        skipWhitespace()
        if i < bytes.count, bytes[i] == UInt8(ascii: "}") {
            i += 1; depth -= 1
            return .object(object)
        }
        while true {
            skipWhitespace()
            guard i < bytes.count, bytes[i] == UInt8(ascii: "\"") else { throw fail("expected a string key") }
            let key = try parseString()
            skipWhitespace()
            guard i < bytes.count, bytes[i] == UInt8(ascii: ":") else { throw fail("expected ':'") }
            i += 1
            skipWhitespace()
            object[key] = try parseValue()
            skipWhitespace()
            guard i < bytes.count else { throw fail("unexpected end of input") }
            if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
            if bytes[i] == UInt8(ascii: "}") { i += 1; depth -= 1; return .object(object) }
            throw fail("expected ',' or '}'")
        }
    }

    mutating func parseArray() throws(JSONParseError) -> JSONValue {
        try enter()
        i += 1
        var array: [JSONValue] = []
        skipWhitespace()
        if i < bytes.count, bytes[i] == UInt8(ascii: "]") {
            i += 1; depth -= 1
            return .array(array)
        }
        while true {
            skipWhitespace()
            array.append(try parseValue())
            skipWhitespace()
            guard i < bytes.count else { throw fail("unexpected end of input") }
            if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
            if bytes[i] == UInt8(ascii: "]") { i += 1; depth -= 1; return .array(array) }
            throw fail("expected ',' or ']'")
        }
    }

    mutating func parseNumber() throws(JSONParseError) -> Double {
        let start = i
        func isDigit(_ b: UInt8) -> Bool { b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9") }
        if bytes[i] == UInt8(ascii: "-") { i += 1 }
        guard i < bytes.count, isDigit(bytes[i]) else { throw fail("invalid number") }
        if bytes[i] == UInt8(ascii: "0") {
            i += 1
        } else {
            while i < bytes.count, isDigit(bytes[i]) { i += 1 }
        }
        if i < bytes.count, bytes[i] == UInt8(ascii: ".") {
            i += 1
            guard i < bytes.count, isDigit(bytes[i]) else { throw fail("invalid number") }
            while i < bytes.count, isDigit(bytes[i]) { i += 1 }
        }
        if i < bytes.count, bytes[i] == UInt8(ascii: "e") || bytes[i] == UInt8(ascii: "E") {
            i += 1
            if i < bytes.count, bytes[i] == UInt8(ascii: "+") || bytes[i] == UInt8(ascii: "-") { i += 1 }
            guard i < bytes.count, isDigit(bytes[i]) else { throw fail("invalid number") }
            while i < bytes.count, isDigit(bytes[i]) { i += 1 }
        }
        let text = String(decoding: bytes[start..<i], as: UTF8.self)
        guard let value = Double(text) else { throw fail("invalid number") }
        return value  // may be ±infinity for huge exponents, like JSON.parse
    }

    mutating func parseString() throws(JSONParseError) -> String {
        i += 1  // opening quote
        var scalars = String.UnicodeScalarView()
        var runStart = i
        func flush(_ end: Int) {
            scalars.append(contentsOf: String(decoding: bytes[runStart..<end], as: UTF8.self).unicodeScalars)
        }
        while true {
            guard i < bytes.count else { throw fail("unterminated string") }
            let b = bytes[i]
            if b == UInt8(ascii: "\"") {
                flush(i)
                i += 1
                return String(scalars)
            }
            if b < 0x20 { throw fail("control character in string") }
            if b != UInt8(ascii: "\\") { i += 1; continue }
            flush(i)
            i += 1
            guard i < bytes.count else { throw fail("unterminated escape") }
            let e = bytes[i]
            i += 1
            switch e {
            case UInt8(ascii: "\""): scalars.append("\"")
            case UInt8(ascii: "\\"): scalars.append("\\")
            case UInt8(ascii: "/"): scalars.append("/")
            case UInt8(ascii: "b"): scalars.append("\u{08}")
            case UInt8(ascii: "f"): scalars.append("\u{0C}")
            case UInt8(ascii: "n"): scalars.append("\n")
            case UInt8(ascii: "r"): scalars.append("\r")
            case UInt8(ascii: "t"): scalars.append("\t")
            case UInt8(ascii: "u"):
                var unit = try hex4()
                if (0xD800...0xDBFF).contains(unit),
                   i + 1 < bytes.count, bytes[i] == UInt8(ascii: "\\"), bytes[i + 1] == UInt8(ascii: "u") {
                    let save = i
                    i += 2
                    let low = try hex4()
                    if (0xDC00...0xDFFF).contains(low) {
                        unit = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
                    } else {
                        i = save
                    }
                }
                // Lone surrogates cannot be represented in a Swift String.
                scalars.append(Unicode.Scalar(unit) ?? "\u{FFFD}")
            default:
                throw fail("invalid escape")
            }
            runStart = i
        }
    }

    mutating func hex4() throws(JSONParseError) -> UInt32 {
        guard i + 4 <= bytes.count else { throw fail("invalid \\u escape") }
        var value: UInt32 = 0
        for _ in 0..<4 {
            let b = bytes[i]
            let digit: UInt32
            switch b {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = UInt32(b - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = UInt32(b - UInt8(ascii: "a") + 10)
            case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = UInt32(b - UInt8(ascii: "A") + 10)
            default: throw fail("invalid \\u escape")
            }
            value = value * 16 + digit
            i += 1
        }
        return value
    }
}
