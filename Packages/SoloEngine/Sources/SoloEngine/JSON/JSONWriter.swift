// JSON output with JavaScript's `JSON.stringify` number and string format, so
// that files written here (sequences, snapshots) read the same as the
// source's. Object keys keep their insertion order.

extension JSONValue {
    /// Compact (`indent == nil`) or indented JSON text. Non-finite numbers
    /// become `null`, as in `JSON.stringify`.
    public func serialized(indent: Int? = nil) -> String {
        var out = ""
        write(&out, indent: indent, level: 0)
        return out
    }

    private func write(_ out: inout String, indent: Int?, level: Int) {
        func newline(_ l: Int) {
            guard let indent else { return }
            out += "\n" + String(repeating: " ", count: indent * l)
        }
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .number(let n): out += n.isFinite ? JSONValue.jsNumber(n) : "null"
        case .string(let s): JSONValue.writeString(s, &out)
        case .array(let a):
            if a.isEmpty { out += "[]"; return }
            out += "["
            for (i, v) in a.enumerated() {
                if i > 0 { out += "," }
                newline(level + 1)
                v.write(&out, indent: indent, level: level + 1)
            }
            newline(level)
            out += "]"
        case .object(let o):
            let entries = o.entries
            if entries.isEmpty { out += "{}"; return }
            out += "{"
            for (i, e) in entries.enumerated() {
                if i > 0 { out += "," }
                newline(level + 1)
                JSONValue.writeString(e.key, &out)
                out += indent == nil ? ":" : ": "
                e.value.write(&out, indent: indent, level: level + 1)
            }
            newline(level)
            out += "}"
        }
    }

    private static func writeString(_ s: String, _ out: inout String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 {
                    let hex = String(u.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else {
                    out.unicodeScalars.append(u)
                }
            }
        }
        out += "\""
    }

    /// ECMAScript `Number::toString` for a finite double: the shortest
    /// round-trip digits (Swift's `description` has the same digits), laid out
    /// with JavaScript's exponent rules.
    public static func jsNumber(_ x: Double) -> String {
        if x == 0 { return "0" }  // also −0
        if x < 0 { return "-" + jsNumber(-x) }
        // Swift: "1.5", "1e-07", "1.2345e+20", "100.0", "5e-324"
        let d = "\(x)"
        var mantissa = Substring(d)
        var exp10 = 0
        if let e = d.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            mantissa = d[..<e]
            exp10 = Int(d[d.index(after: e)...])!
        }
        var intPart = Substring(mantissa), frac = Substring("")
        if let dot = mantissa.firstIndex(of: ".") {
            intPart = mantissa[..<dot]
            frac = mantissa[mantissa.index(after: dot)...]
        }
        // digits and the decimal exponent n: value = 0.digits × 10^n
        var digits = String(intPart) + String(frac)
        var n = intPart.count + exp10
        while digits.hasPrefix("0") && digits.count > 1 {
            digits.removeFirst()
            n -= 1
        }
        while digits.hasSuffix("0") && digits.count > 1 { digits.removeLast() }
        let k = digits.count
        if k <= n && n <= 21 { return digits + String(repeating: "0", count: n - k) }
        if 0 < n && n <= 21 {
            let i = digits.index(digits.startIndex, offsetBy: n)
            return String(digits[..<i]) + "." + String(digits[i...])
        }
        if -6 < n && n <= 0 { return "0." + String(repeating: "0", count: -n) + digits }
        let e = n - 1
        let sign = e < 0 ? "-" : "+"
        let head = String(digits.first!)
        let tail = k > 1 ? "." + String(digits.dropFirst()) : ""
        return head + tail + "e" + sign + String(Swift.abs(e))
    }
}

extension LandmarkSequence {
    /// The fixture / recording file form (ref 04, specs/03). v2 writes the
    /// joints the skeleton lacks and absent world data as `null`; a missing
    /// point of a joint the skeleton has is written unseen (zeros, visibility
    /// 0), since such joints cannot be `null` (specs/03). v1 writes every point.
    public var json: JSONValue {
        let present = skeleton.landmarks
        func points(_ ls: [Landmark], nullable: Bool) -> JSONValue {
            .array(ls.enumerated().map { i, l in
                if nullable && l.isMissing {
                    return present.contains(LandmarkName.allCases[i]) ? ["x": 0, "y": 0, "z": 0, "visibility": 0] : .null
                }
                return ["x": .number(l.x), "y": .number(l.y), "z": .number(l.z), "visibility": .number(l.visibility)]
            })
        }
        let v2 = formatVersion == 2
        var o: JSONValue = ["formatVersion": .number(Double(formatVersion))]
        if v2 {
            o["skeleton"] = .string(skeleton.rawValue)
            o["imageAspect"] = .number(imageAspect)
            if let meta { o["meta"] = meta.json }
            if let reflex { o["reflex"] = reflex.json }
        }
        o["exerciseId"] = .string(exerciseId)
        o["source"] = .string(source.rawValue)
        o["view"] = .string(view.rawValue)
        o["fps"] = .number(fps)
        if let labels {
            o["labels"] = ["reps": .array(labels.map {
                var l: JSONValue = ["outcome": .string($0.outcome.rawValue), "faults": .array($0.faults.map { .string($0) })]
                if let span = $0.span { l["span"] = .array(span.map { .number($0) }) }
                return l
            })]
        }
        o["frames"] = .array(frames.map { f in
            var frame: JSONValue = ["t": .number(f.t), "image": points(f.image, nullable: v2)]
            frame["world"] = v2 && !hasWorld ? .null : points(f.world, nullable: v2)
            return frame
        })
        return o
    }
}
