package swiftcompiler;

#if (macro || reflaxe_runtime)
/**
    Source of the runtime module emitted next to the generated files.
    It only hosts what the translatable subset cannot express inline:
    the Int64 bit representation (stdlib/05), the growable byte sink
    behind haxe.io.BytesBuffer (stdlib/02), the exception base class of
    features/06, and the unit-order string comparison the ordering
    ruling of docs/specs/features/07-numeric-tower.md requires (native operators
    compare canonical order). Resident modules compile through the
    normal pipeline and append after this prelude.
**/
class SwiftRuntime {
    public static final SOURCE = '/// The two 32-bit halves of a binary64 value (stdlib/05). The halves
/// carry the bit patterns as Int32 so they flow into Int32 arithmetic
/// at the codec boundaries without conversions.
public struct Int64Halves {
    public let high: Int32
    public let low: Int32
}

public func doubleToI64(_ value: Double) -> Int64Halves {
    let bits = value.bitPattern
    return Int64Halves(
        high: Int32(bitPattern: UInt32(truncatingIfNeeded: bits >> 32)),
        low: Int32(bitPattern: UInt32(truncatingIfNeeded: bits)))
}

public func i64ToDouble(_ low: Int32, _ high: Int32) -> Double {
    let highWord = UInt64(UInt32(bitPattern: high))
    let lowWord = UInt64(UInt32(bitPattern: low))
    return Double(bitPattern: (highWord << 32) | lowWord)
}

/// The f32-lane value edges (feature spec 23): decode to the f64 value,
/// then round once to the module real; the reverse widens losslessly
/// before the bit conversion. Only the float-precision=f32 lane
/// references them.
public func i64ToF32(_ low: Int32, _ high: Int32) -> Float {
    return Float(i64ToDouble(low, high))
}

public func f32ToI64(_ value: Float) -> Int64Halves {
    return doubleToI64(Double(value))
}

/// The binary32 bit pattern of a float as a signed 32-bit integer, and
/// its inverse (stdlib/05). The Haxe FPHelper edges are binary32 even
/// on the f64 lane, so the same pair serves both configurations.
public func floatToI32(_ value: Double) -> Int32 {
    return Int32(bitPattern: Float(value).bitPattern)
}

public func i32ToFloat(_ bits: Int32) -> Double {
    return Double(Float(bitPattern: UInt32(bitPattern: bits)))
}

/// The f32 module real is already binary32, so its bit edges read the
/// native pattern without a narrowing step.
public func floatToI32F32(_ value: Float) -> Int32 {
    return Int32(bitPattern: value.bitPattern)
}

public func i32ToFloatF32(_ bits: Int32) -> Float {
    return Float(bitPattern: UInt32(bitPattern: bits))
}

/// The growable byte sink behind haxe.io.BytesBuffer (stdlib/02).
/// Array value semantics make the slice returned by getBytes immune to
/// later appends through copy-on-write, so no defensive copy runs.
public final class BytesBuffer {
    private var bytes: [UInt8] = []

    public init() {
    }

    public func addByte(_ byte: Int32) -> Void {
        bytes.append(UInt8(bitPattern: Int8(truncatingIfNeeded: byte)))
    }

    public func add(_ bytes: [UInt8]) -> Void {
        self.bytes.append(contentsOf: bytes)
    }

    public func getBytes() -> [UInt8] {
        return bytes
    }
}

/// Base class of the exception classes features/06 lowers; the caught
/// side reads the display message through it. The base stays non-final
/// because the generated exception classes subclass it.
public class BoringException: Error {
    public let message: String
    public let cause: BoringException?

    public init(message: String, cause: BoringException? = nil) {
        self.message = message
        self.cause = cause
    }
}

/// UTF-16 code-unit ordering of two strings, the order stdlib/07
/// rules for sorted keys. Native comparison operators order by Unicode
/// canonical equivalence instead, so this helper walks both UTF-16
/// views in lockstep. Generic over the two collections so the same
/// body serves String and Array<UInt16> subjects; specialization
/// removes the generics at compile time.
public func unitOrderCompare<A: Collection, B: Collection>(_ a: A, _ b: B) -> Int32
        where A.Element == UInt16, B.Element == UInt16 {
    var ia = a.startIndex
    var ib = b.startIndex
    while ia != a.endIndex && ib != b.endIndex {
        let left = a[ia]
        let right = b[ib]
        if left != right {
            return left < right ? -1 : 1
        }
        a.formIndex(after: &ia)
        b.formIndex(after: &ib)
    }
    if ia == a.endIndex && ib == b.endIndex {
        return 0
    }
    return ia == a.endIndex ? -1 : 1
}

public func compareUnitOrder(_ a: String, _ b: String) -> Int32 {
    return unitOrderCompare(a.utf16, b.utf16)
}

public func compareUnitOrder(_ a: [UInt16], _ b: [UInt16]) -> Int32 {
    return unitOrderCompare(a, b)
}

/// Canonical float spelling used by generated business modules.
public func formatFloatRuntime(_ v: Double) -> [UInt16] {
    if v.isNaN { return Array("NaN".utf16) }
    if v == Double.infinity { return Array("Infinity".utf16) }
    if v == -Double.infinity { return Array("-Infinity".utf16) }
    if v == 0.0 { return Array("0".utf16) }
    var chars = Array(String(v))
    let negative = chars.first == "-"
    if negative { chars.removeFirst() }
    let marker = chars.firstIndex(where: { $0 == "e" || $0 == "E" })
    var exponent = 0
    if let marker {
        exponent = Int(String(chars[(marker + 1)...])) ?? 0
        chars.removeSubrange(marker...)
    }
    let dot = chars.firstIndex(of: ".") ?? chars.count
    var digits = chars.filter { $0 != "." }
    var position = dot + exponent
    while digits.count > 1 && digits.first == "0" { digits.removeFirst(); position -= 1 }
    if position >= -5 && position <= 21 {
        var plain: String
        if position <= 0 { plain = "0." + String(repeating: "0", count: -position) + String(digits) }
        else if position >= digits.count { plain = String(digits) + String(repeating: "0", count: position - digits.count) }
        else { plain = String(digits[..<position]) + "." + String(digits[position...]) }
        while plain.contains(".") && plain.last == "0" { plain.removeLast() }
        if plain.last == "." { plain.removeLast() }
        return Array(((negative ? "-" : "") + plain).utf16)
    }
    while digits.count > 1 && digits.last == "0" { digits.removeLast() }
    let sci = position - 1
    let mantissa = digits.count == 1 ? String(digits) : String(digits[0]) + "." + String(digits.dropFirst())
    return Array(((negative ? "-" : "") + mantissa + "e" + (sci >= 0 ? "+" : "") + String(sci)).utf16)
}

public func formatFloatRuntime(_ v: Float) -> [UInt16] {
    return formatFloatRuntime(Double(v))
}

/// Std.parseInt checked Haxe semantics, kept named so the Swift type
/// checker does not have to solve the complete parser at every call site.
public func parseIntRuntime(_ s: String) -> Int32? {
    let all = Array(s.unicodeScalars)
    func isSpace(_ v: UInt32) -> Bool { return v == 32 || (v >= 9 && v <= 13) }
    var left = 0
    var right = all.count
    while left < right && isSpace(all[left].value) { left += 1 }
    while right > left && isSpace(all[right - 1].value) { right -= 1 }
    let scalars = Array(all[left..<right])
    var start = 0
    var negative = false
    if start < scalars.count && (scalars[start].value == 45 || scalars[start].value == 43) {
        negative = scalars[start].value == 45
        start += 1
    }
    let hex = start + 1 < scalars.count && scalars[start].value == 48
        && (scalars[start + 1].value == 120 || scalars[start + 1].value == 88)
    if hex { start += 2 }
    if start == scalars.count { return nil }
    for i in start..<scalars.count {
        let v = scalars[i].value
        let valid = (v >= 48 && v <= 57) || (hex && ((v >= 65 && v <= 70) || (v >= 97 && v <= 102)))
        if !valid { return nil }
    }
    let digits = String(String.UnicodeScalarView(scalars[start..<scalars.count]))
    guard let n = Int64(digits, radix: hex ? 16 : 10) else { return nil }
    let value = negative ? -n : n
    return value >= -2147483648 && value <= 2147483647 ? Int32(value) : nil
}

/// Unit-indexed reads and cuts over native String, the business face
/// of the UTF-16 view: an index advances through the view because the
/// indices are opaque. Both specialize away at compile time.
public func unitAt(_ s: String, _ index: Int32) -> Int32 {
    let u = s.utf16
    if index < 0 || index >= Int32(u.count) { return 0 }
    return Int32(u[u.index(u.startIndex, offsetBy: Int(index))])
}

public func unitAtOptional(_ s: String, _ index: Int32) -> Int32? {
    let u = s.utf16
    if index < 0 || index >= Int32(u.count) { return nil }
    return Int32(u[u.index(u.startIndex, offsetBy: Int(index))])
}

public func substringUnits(_ s: String, _ start: Int32, _ end: Int32) -> String {
    let u = s.utf16
    var from = start < 0 ? 0 : start
    var to = end < 0 ? 0 : end
    if from > to { let tmp = from; from = to; to = tmp }
    if from >= Int32(u.count) { return "" }
    if to > Int32(u.count) { to = Int32(u.count) }
    let f = u.index(u.startIndex, offsetBy: Int(from))
    let t = u.index(u.startIndex, offsetBy: Int(to))
    return String(decoding: u[f..<t], as: UTF16.self)
}

/// substr over UTF-16 units: a negative pos counts from the end, an
/// omitted len runs to the end, and a negative len yields the empty
/// string, matching the JavaScript target where the std leaves the
/// negative len unspecified.
public func substrUnits(_ s: String, _ pos: Int32, _ len: Int32?) -> String {
    let u = s.utf16
    let count = Int32(u.count)
    var from = pos < 0 ? count + pos : pos
    if from < 0 { from = 0 }
    if from > count { from = count }
    if let l = len {
        if l < 0 { return "" }
        var to = from + l
        if to > count { to = count }
        let f = u.index(u.startIndex, offsetBy: Int(from))
        let t = u.index(u.startIndex, offsetBy: Int(to))
        return String(decoding: u[f..<t], as: UTF16.self)
    }
    let f = u.index(u.startIndex, offsetBy: Int(from))
    return String(decoding: u[f...], as: UTF16.self)
}

/// The resident unit-array reading of the same substr contract.
public func substrUnitsArray(_ s: [UInt16], _ pos: Int32, _ len: Int32?) -> [UInt16] {
    let count = Int32(s.count)
    var from = pos < 0 ? count + pos : pos
    if from < 0 { from = 0 }
    if from > count { from = count }
    if let l = len {
        if l < 0 { return [] }
        var to = from + l
        if to > count { to = count }
        return Array(s[Int(from)..<Int(to)])
    }
    return Array(s[Int(from)...])
}

/// The code point at a unit cursor of the resident unit array: a
/// well-formed surrogate pair combines into its scalar, anything else
/// reads as the single unit (docs/specs/stdlib/10-unicode-string-access.md
/// keeps `codeAt` the pair-combining read on every UTF-16 target).
public func unitCodePoint(_ s: [UInt16], _ index: Int32) -> Int32 {
    let high = s[Int(index)]
    if high >= 0xD800 && high <= 0xDBFF && Int(index) + 1 < s.count {
        let low = s[Int(index) + 1]
        if low >= 0xDC00 && low <= 0xDFFF {
            return Int32(0x10000 + (Int32(high - 0xD800) << 10)) + Int32(low - 0xDC00)
        }
    }
    return Int32(high)
}

';

    /**
        Code-point-addressed helpers behind std.UStringRT (stdlib/10),
        emitted only when the UStringRT resident is absent from the
        compilation: a compilation that includes the resident provides
        the same members, and a second declaration would collide.
    **/
    public static final USTRING_PRELUDE = '/// Code-point-addressed access behind std.UStringRT (stdlib/10). The
/// generated call sites materialize the subject once into its UTF-16
/// units; the helpers address characters, so a surrogate pair occupies
/// one position and combines into one scalar value.
public enum UString {
    /// The number of characters: every unit except the low half of a
    /// surrogate pair starts one character.
    public static func count(_ units: [UInt16]) -> Int32 {
        var total: Int32 = 0
        var i = 0
        while i < units.count {
            total += 1
            i += (units[i] >= 0xD800 && units[i] <= 0xDBFF) ? 2 : 1
        }
        return total
    }

    /// The character at `index`; nil when the position is negative or at
    /// least the character count (the query-miss contract of stdlib/10).
    public static func at(_ units: [UInt16], _ index: Int32) -> Int32? {
        if index < 0 {
            return nil
        }
        var remaining = index
        var i = 0
        while i < units.count {
            let unit = units[i]
            if unit >= 0xD800 && unit <= 0xDBFF {
                if remaining == 0 {
                    if i + 1 >= units.count {
                        return nil
                    }
                    let low = units[i + 1]
                    return Int32(0x10000 + (Int32(unit - 0xD800) << 10)) + Int32(low - 0xDC00)
                }
                remaining -= 1
                i += 2
            } else {
                if remaining == 0 {
                    return Int32(unit)
                }
                remaining -= 1
                i += 1
            }
        }
        return nil
    }

    /// The characters from `from` inclusive to `to` exclusive; `from`
    /// clamps upward to 0, `to` clamps downward to the character count,
    /// and an empty range yields the empty array.
    public static func slice(_ units: [UInt16], _ from: Int32, _ to: Int32) -> [UInt16] {
        let lo = from > 0 ? from : 0
        let hi = to < count(units) ? to : count(units)
        if lo >= hi {
            return []
        }
        var out: [UInt16] = []
        var position: Int32 = 0
        var i = 0
        while i < units.count {
            let width = (units[i] >= 0xD800 && units[i] <= 0xDBFF) ? 2 : 1
            if position >= hi {
                break
            }
            if position >= lo {
                out.append(units[i])
                if width == 2 && i + 1 < units.count {
                    out.append(units[i + 1])
                }
            }
            position += 1
            i += width
        }
        return out
    }
}
';

    /**
        Source of the test host emitted beside the runtime module. It
        holds the raise type of this language, the runner state, and the
        result-line edge to stdout; the consistency run redirects stdout
        to the jsonl results file. Assertion checks and canonical
        formatting live in TestCore, appended after this host in this
        same file.
    **/
    /** Canonical compiled TestCore swift text, used verbatim when the
        build never types runtime.TestCore but the runner references it.
        (TestCoreFallbackSource) */
    public static final TEST_CORE_FALLBACK = 'public enum TestCore {\n    public static func ok(_ condition: Bool, _ message: [UInt16]) throws -> Void {\n        if !condition {\n            throw TestFailure(message: TestCore.formatCanonicalMessage(Test.currentTestIdState(), message, Array(\"\".utf16), Array(\"\".utf16), false))\n        }\n    }\n\n    public static func fail(_ message: [UInt16]) throws -> Void {\n        throw TestFailure(message: TestCore.formatCanonicalMessage(Test.currentTestIdState(), message, Array(\"\".utf16), Array(\"\".utf16), false))\n    }\n\n    public static func equalsBool(_ expected: Bool, _ actual: Bool, _ message: [UInt16]) throws -> Void {\n        if expected != actual {\n            throw TestFailure(message: TestCore.formatCanonicalMessage(Test.currentTestIdState(), message, TestCore.formatBool(expected), TestCore.formatBool(actual), true))\n        }\n    }\n\n    public static func equalsInt(_ expected: Int32, _ actual: Int32, _ message: [UInt16]) throws -> Void {\n        if expected != actual {\n            throw TestFailure(message: TestCore.formatCanonicalMessage(Test.currentTestIdState(), message, TestCore.formatInt(expected), TestCore.formatInt(actual), true))\n        }\n    }\n\n    public static func equalsFloat(_ expected: Double, _ actual: Double, _ message: [UInt16]) throws -> Void {\n        if expected != actual {\n            throw TestFailure(message: TestCore.formatCanonicalMessage(Test.currentTestIdState(), message, TestCore.formatFloat(expected), TestCore.formatFloat(actual), true))\n        }\n    }\n\n    public static func equalsString(_ expected: [UInt16], _ actual: [UInt16], _ message: [UInt16]) throws -> Void {\n        if expected != actual {\n            throw TestFailure(message: TestCore.formatCanonicalMessage(Test.currentTestIdState(), message, TestCore.formatString(expected), TestCore.formatString(actual), true))\n        }\n    }\n\n    public static func reportFailure(_ message: [UInt16], _ expectedStr: [UInt16], _ actualStr: [UInt16]) throws -> Void {\n        throw TestFailure(message: TestCore.formatCanonicalMessage(Test.currentTestIdState(), message, expectedStr, actualStr, true))\n    }\n\n    public static func formatBool(_ v: Bool) -> [UInt16] {\n        if v {\n            return Array(\"true\".utf16)\n        }\n        return Array(\"false\".utf16)\n    }\n\n    public static func formatInt(_ v: Int32) -> [UInt16] {\n        return Array(String(v).utf16)\n    }\n\n    public static func formatFloat(_ v: Double) -> [UInt16] {\n        if v != v {\n            return Array(\"NaN\".utf16)\n        }\n        if v == Double.infinity {\n            return Array(\"Infinity\".utf16)\n        }\n        if v == -Double.infinity {\n            return Array(\"-Infinity\".utf16)\n        }\n        if v == 0.0 {\n            return Array(\"0\".utf16)\n        }\n        let raw = Array(String(v).utf16)\n        var s = raw\n        var negative = false\n        if Int32(s[Int(0)]) == 45 {\n            negative = true\n            s = Array(s[max(0, Int(1))...])\n        }\n        let exponentParts = TiqianArray(s.split(separator: Array(\"e\".utf16).first!, omittingEmptySubsequences: false).map { Array($0) })\n        var exponent: Int32 = 0\n        if Int32(exponentParts.count) == 2 {\n            let exponentText = exponentParts[Int(1)]\n            let exponentValue: Int32? = parseIntRuntime(String(decoding: exponentText, as: UTF16.self))\n            exponent = exponentValue ?? 0\n            s = exponentParts[Int(0)]\n        }\n        let decimalParts = TiqianArray(s.split(separator: Array(\".\".utf16).first!, omittingEmptySubsequences: false).map { Array($0) })\n        let hasDot = Int32(decimalParts.count) == 2\n        var fraction = Array(\"\".utf16)\n        if hasDot {\n            fraction = decimalParts[Int(1)]\n        }\n        var digits = { let p0 = decimalParts[Int(0)]; let p1 = fraction; return p0 + p1 }()\n        var decimalPosition: Int32 = Int32(decimalParts[Int(0)].count) &+ exponent\n        while Int32(digits.count) > 1 && Int32(digits[Int(0)]) == 48 {\n            digits = Array(digits[max(0, Int(1))...])\n            decimalPosition -= 1\n        }\n        if digits == Array(\"0\".utf16) {\n            return Array(\"0\".utf16)\n        }\n        if decimalPosition >= -5 && decimalPosition <= 21 {\n            var plain = (decimalPosition <= 0 ? TestCore.plainLeading(digits, decimalPosition) : (decimalPosition >= Int32(digits.count) ? TestCore.plainTrailing(digits, decimalPosition) : { let p0 = Array(digits[Int(0)..<Int(decimalPosition)]); let p1 = Array(\".\".utf16); let p2 = Array(digits[max(0, Int(decimalPosition))...]); return p0 + p1 + p2 }()))\n            while Int32(plain.count) > 0 && Int32(plain[Int(Int32(plain.count) &- 1)]) == 48 && Int32(TiqianArray(plain.split(separator: Array(\".\".utf16).first!, omittingEmptySubsequences: false).map { Array($0) }).count) > 1 {\n                plain = Array(plain[Int(0)..<Int(Int32(plain.count) &- 1)])\n            }\n            if Int32(plain.count) > 0 && Int32(plain[Int(Int32(plain.count) &- 1)]) == 46 {\n                plain = Array(plain[Int(0)..<Int(Int32(plain.count) &- 1)])\n            }\n            return { let p0 = (negative ? Array(\"-\".utf16) : Array(\"\".utf16)); let p1 = plain; return p0 + p1 }()\n        }\n        while Int32(digits.count) > 1 && Int32(digits[Int(Int32(digits.count) &- 1)]) == 48 {\n            digits = Array(digits[Int(0)..<Int(Int32(digits.count) &- 1)])\n        }\n        let sciExponent: Int32 = decimalPosition &- 1\n        let mantissa = (Int32(digits.count) == 1 ? digits : { let p0 = Array(digits[Int(0)..<Int(1)]); let p1 = Array(\".\".utf16); let p2 = Array(digits[max(0, Int(1))...]); return p0 + p1 + p2 }())\n        return { let p0 = (negative ? Array(\"-\".utf16) : Array(\"\".utf16)); let p1 = mantissa; let p2 = Array(\"e\".utf16); let p3 = (sciExponent >= 0 ? Array(\"+\".utf16) : Array(\"\".utf16)); let p4 = TestCore.formatInt(sciExponent); return p0 + p1 + p2 + p3 + p4 }()\n    }\n\n    private static func plainLeading(_ digits: [UInt16], _ decimalPosition: Int32) -> [UInt16] {\n        var head = Array(\"0.\".utf16)\n        for _ in stride(from: Int32(0), to: -decimalPosition, by: 1) {\n            head += Array(\"0\".utf16)\n        }\n        return { let p0 = head; let p1 = digits; return p0 + p1 }()\n    }\n\n    private static func plainTrailing(_ digits: [UInt16], _ decimalPosition: Int32) -> [UInt16] {\n        var tail = Array(\"\".utf16)\n        for _ in stride(from: Int32(0), to: decimalPosition &- Int32(digits.count), by: 1) {\n            tail += Array(\"0\".utf16)\n        }\n        return { let p0 = digits; let p1 = tail; return p0 + p1 }()\n    }\n\n    public static func formatString(_ v: [UInt16]) -> [UInt16] {\n        return { let p0 = Array(\"\\\"\".utf16); let p1 = TestCore.escapeJson(v); let p2 = Array(\"\\\"\".utf16); return p0 + p1 + p2 }()\n    }\n\n    public static func formatBytes(_ b: [UInt8]) -> [UInt16] {\n        var out = Array(\"\".utf16)\n        for index in stride(from: Int32(0), to: Int32(b.count), by: 1) {\n            let value: Int32 = Int32(b[Int(index)])\n            out += TestCore.hexDigit(value >> 4 & 15)\n            out += TestCore.hexDigit(value & 15)\n        }\n        return out\n    }\n\n    public static func escapeJson(_ s: [UInt16]) -> [UInt16] {\n        var out = Array(\"\".utf16)\n        var cursor: Int32 = 0\n        let stop: Int32 = Int32(s.count)\n        while cursor < stop {\n            let code: Int32 = unitCodePoint(s, cursor)\n            if code == 34 {\n                out += Array(\"\\\\\\\"\".utf16)\n            } else if code == 92 {\n                out += Array(\"\\\\\\\\\".utf16)\n            } else if code == 10 {\n                out += Array(\"\\\\n\".utf16)\n            } else if code == 13 {\n                out += Array(\"\\\\r\".utf16)\n            } else if code == 9 {\n                out += Array(\"\\\\t\".utf16)\n            } else if code < 32 {\n                out += { let p0 = Array(\"\\\\u\".utf16); let p1 = TestCore.hexDigit(code >> 12 & 15); let p2 = TestCore.hexDigit(code >> 8 & 15); let p3 = TestCore.hexDigit(code >> 4 & 15); let p4 = TestCore.hexDigit(code & 15); return p0 + p1 + p2 + p3 + p4 }()\n            } else {\n                out += Array(s[Int(cursor)..<Int((cursor + Int32(unitCodePoint(s, cursor) > 0xFFFF ? 2 : 1)))])\n            }\n            cursor = (cursor + Int32(unitCodePoint(s, cursor) > 0xFFFF ? 2 : 1))\n        }\n        return out\n    }\n\n    public static func formatCanonicalMessage(_ id: [UInt16], _ message: [UInt16], _ expectedStr: [UInt16], _ actualStr: [UInt16], _ isEquals: Bool) -> [UInt16] {\n        var out = { let p0 = Array(\"test failed: \".utf16); let p1 = id; return p0 + p1 }()\n        if message != Array(\"\".utf16) {\n            out += { let p0 = Array(\"\\n  message: \".utf16); let p1 = message; return p0 + p1 }()\n        }\n        if isEquals {\n            out += { let p0 = Array(\"\\n  expected: \".utf16); let p1 = expectedStr; return p0 + p1 }()\n            out += { let p0 = Array(\"\\n  actual:   \".utf16); let p1 = actualStr; return p0 + p1 }()\n        }\n        return out\n    }\n\n    public static func resultLine(_ id: [UInt16], _ name: [UInt16], _ failed: Bool, _ message: [UInt16]) -> [UInt16] {\n        if failed {\n            return { let p0 = Array(\"{\\\"id\\\":\\\"\".utf16); let p1 = TestCore.escapeJson(id); let p2 = Array(\"\\\",\\\"name\\\":\\\"\".utf16); let p3 = TestCore.escapeJson(name); let p4 = Array(\"\\\",\\\"verdict\\\":\\\"fail\\\",\\\"message\\\":\\\"\".utf16); let p5 = TestCore.escapeJson(message); let p6 = Array(\"\\\"}\\n\".utf16); return p0 + p1 + p2 + p3 + p4 + p5 + p6 }()\n        }\n        return { let p0 = Array(\"{\\\"id\\\":\\\"\".utf16); let p1 = TestCore.escapeJson(id); let p2 = Array(\"\\\",\\\"name\\\":\\\"\".utf16); let p3 = TestCore.escapeJson(name); let p4 = Array(\"\\\",\\\"verdict\\\":\\\"pass\\\"}\\n\".utf16); return p0 + p1 + p2 + p3 + p4 }()\n    }\n\n    public static func notApplicableLine(_ id: [UInt16], _ name: [UInt16]) -> [UInt16] {\n        return { let p0 = Array(\"{\\\"id\\\":\\\"\".utf16); let p1 = TestCore.escapeJson(id); let p2 = Array(\"\\\",\\\"name\\\":\\\"\".utf16); let p3 = TestCore.escapeJson(name); let p4 = Array(\"\\\",\\\"verdict\\\":\\\"not_applicable\\\"}\\n\".utf16); return p0 + p1 + p2 + p3 + p4 }()\n    }\n\n    private static func hexDigit(_ nibble: Int32) -> [UInt16] {\n        if nibble < 10 {\n            return ((48 &+ nibble >= 0 && 48 &+ nibble <= 1114111 && !(48 &+ nibble >= 55296 && 48 &+ nibble <= 57343)) ? (48 &+ nibble > 65535 ? [UInt16(55296 + ((48 &+ nibble - 65536) >> 10)), UInt16(56320 + (48 &+ nibble & 1023))] : [UInt16(48 &+ nibble)]) : [UInt16(0)])\n        }\n        return ((87 &+ nibble >= 0 && 87 &+ nibble <= 1114111 && !(87 &+ nibble >= 55296 && 87 &+ nibble <= 57343)) ? (87 &+ nibble > 65535 ? [UInt16(55296 + ((87 &+ nibble - 65536) >> 10)), UInt16(56320 + (87 &+ nibble & 1023))] : [UInt16(87 &+ nibble)]) : [UInt16(0)])\n    }\n}';

    public static final TEST_SOURCE = '

// The C library of the host, for the environment read below. This file is
// written on its own, without the header the generated modules carry, so
// the conditional imports live here.
#if canImport(Glibc)
import Glibc
#endif
#if canImport(Darwin)
import Darwin
#endif
#if canImport(CRT)
import CRT
#endif

/// The text of an environment variable, or nil when it is unset. The
/// platform calls match the ones the std.Env host edge uses.
func boringTestEnvText(_ key: String) -> String? {
    #if canImport(Glibc) || canImport(Darwin)
    return key.withCString { k in
        guard let value = getenv(k) else { return nil }
        return String(cString: value)
    }
    #elseif canImport(CRT)
    return key.withCString { k in
        var buffer: UnsafeMutablePointer<CChar>? = nil
        var count: Int = 0
        if _dupenv_s(&buffer, &count, k) == 0, let buffer {
            defer { free(buffer) }
            return String(cString: buffer)
        }
        return nil
    }
    #else
    return nil
    #endif
}

/// The wall-clock budget of one test in milliseconds, read from the
/// environment on every run and never at generation time, so one generated
/// tree serves every budget. A value that is absent, unparsable, or not
/// positive falls back to 5000. The generated entry carries no runner timer
/// of its own, so this check is the only timeout a body that returned late
/// is caught by.
func boringTestTimeoutBudgetMs() -> Int {
    if let raw = boringTestEnvText("BORING_TEST_TIMEOUT_MS"), let parsed = Int(raw), parsed > 0 {
        return parsed
    }
    return 5000
}

/// The wall-clock milliseconds since the given instant. The standard
/// library clock is monotonic, so no platform timer API enters the runtime.
func boringTestElapsedMs(since start: ContinuousClock.Instant) -> Int {
    let elapsed = start.duration(to: ContinuousClock().now)
    return Int(elapsed.components.seconds) * 1000 + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
}

/// The assertion failure of features/19: the canonical message in the
/// resident unit-array ABI, converted to text only at the print edge.
public struct TestFailure: Error {
    public let message: [UInt16]

    public init(message: [UInt16]) {
        self.message = message
    }
}

func decodeUnits(_ units: [UInt16]) -> String {
    return String(decoding: units, as: UTF16.self)
}

public enum Test {
    private static var currentTestId: [UInt16] = []

    // Host edges of the test entry (features/19): the runner state, the
    // raise of this language, and the stdout result edge. Assertion
    // checks and scalar formatting live in TestCore, appended after
    // this enum in this same file.
    public static func currentTestIdState() -> [UInt16] {
        return Test.currentTestId
    }

    // A test this target excludes (features/19): the entry does not run
    // the body and writes the not-applicable record instead, so the id
    // stays in the cross-target set.
    public static func recordNotApplicable(_ id: String, _ name: String) {
        print(decodeUnits(TestCore.notApplicableLine(Array(id.utf16), Array(name.utf16))), terminator: "")
    }

    public static func run(_ id: String, _ name: String, _ body: () throws -> Void) -> Bool {
        let idUnits = Array(id.utf16)
        let nameUnits = Array(name.utf16)
        Test.currentTestId = idUnits
        let budgetMs = boringTestTimeoutBudgetMs()
        let startedAt = ContinuousClock().now
        // The result line carries its own newline; an empty terminator
        // keeps one record per line in the redirected results file.
        do {
            try body()
            if boringTestElapsedMs(since: startedAt) >= budgetMs {
                // A body that returned at or past the budget raises the
                // failure type of an assertion, so the clause below records
                // the fail line with the timeout message and the runner
                // reports the test as failed too.
                let text = "this test timed out after " + String(budgetMs) + "ms"
                throw TestFailure(message: Array(text.utf16))
            }
            print(decodeUnits(TestCore.resultLine(idUnits, nameUnits, false, [])), terminator: "")
            Test.currentTestId = []
            return false
        } catch let error as TestFailure {
            print(decodeUnits(TestCore.resultLine(idUnits, nameUnits, true, error.message)), terminator: "")
            Test.currentTestId = []
            return true
        } catch let error as BoringException {
            print(decodeUnits(TestCore.resultLine(idUnits, nameUnits, true, Array(error.message.utf16))), terminator: "")
            Test.currentTestId = []
            return true
        } catch {
            let fallback = String(describing: error)
            print(decodeUnits(TestCore.resultLine(idUnits, nameUnits, true, Array(fallback.utf16))), terminator: "")
            Test.currentTestId = []
            return true
        }
    }
}

/// Reference-semantics array: Haxe Array is a reference type, but Swift
/// [T] is a value type. Every Haxe Array lowers to this class so a value
/// stored in a field and a caller local share one underlying buffer.
/// The class mirrors the [T] API (subscript, count, push, indexOf, ...)
/// so generated code reads naturally instead of spelling out .items.
public final class TiqianArray<Element>: Sequence, Collection {
    public var items: [Element]
    public init() { self.items = [] }
    public init(_ items: [Element]) { self.items = items }

    // Sequence / Collection conformance (for for x in arr).
    public typealias Index = Int
    public var startIndex: Int { return items.startIndex }
    public var endIndex: Int { return items.endIndex }
    public func index(after i: Int) -> Int { return items.index(after: i) }

    // Read/write subscript (arr[i] = v and arr[i]). Both the Collection
    // conformance above and the Haxe indexed read/write both lower to this
    // declaration; a second read-only subscript would be a redeclaration.
    public subscript(index: Int) -> Element {
        get { return items[index] }
        set { items[index] = newValue }
    }

    public var count: Int { return items.count }
    public var isEmpty: Bool { return items.isEmpty }
    public var first: Element? { return items.first }
    public var last: Element? { return items.last }

    // Element mutators.
    public func push(_ element: Element) { items.append(element) }
    public func append(_ element: Element) { items.append(element) }
    public func pop() -> Element? { return items.popLast() }
    public func shift() -> Element? { return items.isEmpty ? nil : items.removeFirst() }
    public func unshift(_ element: Element) { items.insert(element, at: 0) }
    public func insert(_ element: Element, at index: Int) {
        // Haxe bounds the position: negative counts from the end and stops
        // at the first element, past-the-end clamps to the count.
        let sz = items.count
        let p = index < 0 ? Swift.max(sz + index, 0) : Swift.min(index, sz)
        items.insert(element, at: p)
    }
    public func remove(at index: Int) -> Element { return items.remove(at: index) }
    public func splice(_ start: Int, _ len: Int) -> TiqianArray<Element> {
        // Haxe splice mutates and returns the removed sub-array, bounding
        // the call before removing: negative length or past-the-end start
        // removes nothing, negative start counts from the end, a length past
        // the end removes only the tail.
        let sz = items.count
        let p0 = start
        let p = p0 < 0 ? Swift.max(sz + p0, 0) : (p0 > sz ? sz : p0)
        let c = (len < 0 || p0 > sz) ? 0 : Swift.min(len, sz - p)
        let removed = Array(items[p..<(p + c)])
        if c > 0 { items.removeSubrange(p..<(p + c)) }
        return TiqianArray(removed)
    }
    public func removeLast() -> Element { return items.removeLast() }
    public func removeFirst() -> Element { return items.removeFirst() }
    public func reverse() { items.reverse() }
    public func reserveCapacity(_ n: Int) { items.reserveCapacity(n) }
    public func sort(by areInIncreasingOrder: (Element, Element) -> Bool) { items.sort(by: areInIncreasingOrder) }

    // Array-producing operations return a fresh TiqianArray.
    public func copy() -> TiqianArray<Element> { return TiqianArray(items) }
    public func concat(_ other: TiqianArray<Element>) -> TiqianArray<Element> { return TiqianArray(items + other.items) }
    public func slice(_ range: Range<Int>) -> TiqianArray<Element> { return TiqianArray(Array(items[range])) }
    public func map<U>(_ transform: (Element) -> U) -> TiqianArray<U> { return TiqianArray<U>(items.map(transform)) }
    public func filter(_ isIncluded: (Element) -> Bool) -> TiqianArray<Element> { return TiqianArray<Element>(items.filter(isIncluded)) }
    public func join(separator: String = "") -> String { return items.map { String(describing: $0) }.joined(separator: separator) }
    // Sequence supplies these too, but its forms return a Swift Array, which
    // no longer matches a Haxe Array slot. Declaring them on the class keeps
    // the container type through the call, as map and filter above already do.
    public func sorted(by areInIncreasingOrder: (Element, Element) -> Bool) -> TiqianArray<Element> {
        return TiqianArray(items.sorted(by: areInIncreasingOrder))
    }
    public func reversed() -> TiqianArray<Element> { return TiqianArray(Array(items.reversed())) }
    public func compactMap<U>(_ transform: (Element) -> U?) -> TiqianArray<U> { return TiqianArray<U>(items.compactMap(transform)) }
}

extension TiqianArray where Element: Comparable {
    public func sorted() -> TiqianArray<Element> { return TiqianArray<Element>(items.sorted()) }
}

// Element equality operations live here so the class body stays free of the
// constraint; Swift only exposes firstIndex(of:)/lastIndex(of:)/contains(_:)
// when the element is Equatable. (TiqianArray)
extension TiqianArray where Element: Equatable {
    public func indexOf(_ element: Element) -> Int32 {
        if let i = items.firstIndex(of: element) { return Int32(items.distance(from: items.startIndex, to: i)) }
        return -1
    }
    public func lastIndexOf(_ element: Element) -> Int32 {
        if let i = items.lastIndex(of: element) { return Int32(items.distance(from: items.startIndex, to: i)) }
        return -1
    }
    public func contains(_ element: Element) -> Bool { return items.contains(element) }
}

// A struct or enum that stores a Haxe Array needs the container to be
// Equatable so Swift can synthesize its own ==. The comparison stays
// element-wise, which is what the [T] representation this class replaced
// already gave, so no equality behaviour changes. (TiqianArray)
extension TiqianArray: Equatable where Element: Equatable {
    public static func == (lhs: TiqianArray<Element>, rhs: TiqianArray<Element>) -> Bool { return lhs.items == rhs.items }
}
';
}
#end
