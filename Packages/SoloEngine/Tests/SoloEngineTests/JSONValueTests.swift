import Foundation
import Testing
@testable import SoloEngine

@Suite("JSONValue") struct JSONValueTests {
    @Test func keepsObjectKeyOrder() throws {
        let v = try JSONValue.parse(#"{"z": 1, "a": 2, "m": {"y": true, "b": null}}"#)
        #expect(v.objectValue?.keys == ["z", "a", "m"])
        #expect(v["m"]?.objectValue?.keys == ["y", "b"])
    }

    @Test func duplicateKeyKeepsFirstPositionAndLastValue() throws {
        let v = try JSONValue.parse(#"{"a": 1, "b": 2, "a": 3}"#)
        #expect(v.objectValue?.keys == ["a", "b"])
        #expect(v["a"] == 3)
    }

    @Test func scalars() throws {
        #expect(try JSONValue.parse("true") == .bool(true))
        #expect(try JSONValue.parse(" null ") == .null)
        #expect(try JSONValue.parse("-0.25e1") == .number(-2.5))
        #expect(try JSONValue.parse("1E2") == .number(100))
        #expect(try JSONValue.parse(#""a\"b\\c\/d\n\u00e7\ud83d\ude00""#) == .string("a\"b\\c/d\nç😀"))
    }

    @Test func booleansAreNotNumbers() throws {
        #expect(try JSONValue.parse("[1, true]") == .array([.number(1), .bool(true)]))
    }

    @Test(arguments: ["", "{", "[1,]", "{\"a\":1,}", "01", "1.", ".5", "+1", "'a'", "{a:1}", "[1] 2",
                      "\"\u{01}\"", "\"\\x\"", "nul", "NaN", "Infinity", "\u{FEFF}{}"])
    func rejectsInvalidJSON(_ text: String) {
        #expect(throws: JSONParseError.self) { try JSONValue.parse(text) }
    }

    @Test func rejectsInvalidUTF8() {
        #expect(throws: JSONParseError.self) { try JSONValue.parse(Data([0x22, 0xFF, 0x22])) }
    }

    @Test func hugeExponentIsInfinityLikeJSONParse() throws {
        #expect(try JSONValue.parse("1e400") == .number(.infinity))
    }

    @Test func mutationHelpers() {
        var v: JSONValue = ["a": [1, 2], "b": ["c": 1]]
        v["a"]![0] = 9
        v["b"]!["c"] = nil
        v["a"]!.append(3)
        #expect(v == ["a": [9, 2, 3], "b": [:]])
    }
}
