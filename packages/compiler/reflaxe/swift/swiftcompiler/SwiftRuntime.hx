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
struct Int64Halves {
    let high: Int32
    let low: Int32
}

func doubleToI64(_ value: Double) -> Int64Halves {
    let bits = value.bitPattern
    return Int64Halves(
        high: Int32(bitPattern: UInt32(truncatingIfNeeded: bits >> 32)),
        low: Int32(bitPattern: UInt32(truncatingIfNeeded: bits)))
}

func i64ToDouble(_ low: Int32, _ high: Int32) -> Double {
    let highWord = UInt64(UInt32(bitPattern: high))
    let lowWord = UInt64(UInt32(bitPattern: low))
    return Double(bitPattern: (highWord << 32) | lowWord)
}

/// The f32-lane value edges (feature spec 23): decode to the f64 value,
/// then round once to the module real; the reverse widens losslessly
/// before the bit conversion. Only the float-precision=f32 lane
/// references them.
func i64ToF32(_ low: Int32, _ high: Int32) -> Float {
    return Float(i64ToDouble(low, high))
}

func f32ToI64(_ value: Float) -> Int64Halves {
    return doubleToI64(Double(value))
}

/// The growable byte sink behind haxe.io.BytesBuffer (stdlib/02).
/// Array value semantics make the slice returned by getBytes immune to
/// later appends through copy-on-write, so no defensive copy runs.
final class BytesBuffer {
    private var bytes: [UInt8] = []

    init() {
    }

    func addByte(_ byte: Int32) -> Void {
        bytes.append(UInt8(bitPattern: Int8(truncatingIfNeeded: byte)))
    }

    func getBytes() -> [UInt8] {
        return bytes
    }
}

/// Base class of the exception classes features/06 lowers; the caught
/// side reads the display message through it. The base stays non-final
/// because the generated exception classes subclass it.
class BoringException: Error {
    let message: String

    init(message: String) {
        self.message = message
    }
}

/// UTF-16 code-unit ordering of two strings, the order stdlib/07
/// rules for sorted keys. Native comparison operators order by Unicode
/// canonical equivalence instead, so this helper walks both UTF-16
/// views in lockstep. Generic over the two collections so the same
/// body serves String and Array<UInt16> subjects; specialization
/// removes the generics at compile time.
func unitOrderCompare<A: Collection, B: Collection>(_ a: A, _ b: B) -> Int32
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

func compareUnitOrder(_ a: String, _ b: String) -> Int32 {
    return unitOrderCompare(a.utf16, b.utf16)
}

func compareUnitOrder(_ a: [UInt16], _ b: [UInt16]) -> Int32 {
    return unitOrderCompare(a, b)
}

/// Std.parseInt checked Haxe semantics, kept named so the Swift type
/// checker does not have to solve the complete parser at every call site.
func parseIntRuntime(_ s: String) -> Int32? {
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
func unitAt(_ s: String, _ index: Int32) -> Int32 {
    let u = s.utf16
    if index < 0 || index >= Int32(u.count) { return 0 }
    return Int32(u[u.index(u.startIndex, offsetBy: Int(index))])
}

func unitAtOptional(_ s: String, _ index: Int32) -> Int32? {
    let u = s.utf16
    if index < 0 || index >= Int32(u.count) { return nil }
    return Int32(u[u.index(u.startIndex, offsetBy: Int(index))])
}

func substringUnits(_ s: String, _ start: Int32, _ end: Int32) -> String {
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
func substrUnits(_ s: String, _ pos: Int32, _ len: Int32?) -> String {
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
func substrUnitsArray(_ s: [UInt16], _ pos: Int32, _ len: Int32?) -> [UInt16] {
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
func unitCodePoint(_ s: [UInt16], _ index: Int32) -> Int32 {
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
		Source of the test host emitted beside the runtime module. It
		holds the raise type of this language, the runner state, and the
		result-line edge to stdout; the consistency run redirects stdout
		to the jsonl results file. Assertion checks and canonical
		formatting live in TestCore, appended after this host in this
		same file.
	**/
	public static final TEST_SOURCE = '

/// The assertion failure of features/19: the canonical message in the
/// resident unit-array ABI, converted to text only at the print edge.
struct TestFailure: Error {
    let message: [UInt16]
}

func decodeUnits(_ units: [UInt16]) -> String {
    return String(decoding: units, as: UTF16.self)
}

enum Test {
    private static var currentTestId: [UInt16] = []

    // Host edges of the test entry (features/19): the runner state, the
    // raise of this language, and the stdout result edge. Assertion
    // checks and scalar formatting live in TestCore, appended after
    // this enum in this same file.
    static func currentTestIdState() -> [UInt16] {
        return Test.currentTestId
    }

    static func run(_ id: String, _ name: String, _ body: () throws -> Void) -> Bool {
        let idUnits = Array(id.utf16)
        let nameUnits = Array(name.utf16)
        Test.currentTestId = idUnits
        // The result line carries its own newline; an empty terminator
        // keeps one record per line in the redirected results file.
        do {
            try body()
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

';
}
#end
