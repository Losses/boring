package swiftcompiler;

#if (macro || reflaxe_runtime)

/**
	Source of the runtime module emitted next to the generated files.
	It only hosts what the translatable subset cannot express inline:
	the Int64 bit representation (stdlib/05), the growable byte sink
	behind haxe.io.BytesBuffer (stdlib/02), the exception base class of
	features/06, and the unit-order string comparison the ordering
	ruling of docs/specs/targets/swift.md requires (native operators
	compare canonical order). Resident modules compile through the
	normal pipeline and append after this prelude.
**/
class SwiftRuntime {
	public static final SOURCE = '

/// The two 32-bit halves of a binary64 value (stdlib/05). The halves
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

/// Unit-indexed reads and cuts over native String, the business face
/// of the UTF-16 view: an index advances through the view because the
/// indices are opaque. Both specialize away at compile time.
func unitAt(_ s: String, _ index: Int32) -> Int32 {
    let u = s.utf16
    return Int32(u[u.index(u.startIndex, offsetBy: Int(index))])
}

func substringUnits(_ s: String, _ start: Int32, _ end: Int32) -> String {
    let u = s.utf16
    let from = u.index(u.startIndex, offsetBy: Int(start))
    let to = u.index(u.startIndex, offsetBy: Int(end))
    return String(decoding: u[from..<to], as: UTF16.self)
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

    static func run(_ id: String, _ name: String, _ body: () throws -> Void) -> Void {
        let idUnits = Array(id.utf16)
        let nameUnits = Array(name.utf16)
        Test.currentTestId = idUnits
        // The result line carries its own newline; an empty terminator
        // keeps one record per line in the redirected results file.
        do {
            try body()
            print(decodeUnits(TestCore.resultLine(idUnits, nameUnits, false, [])), terminator: "")
        } catch let error as TestFailure {
            print(decodeUnits(TestCore.resultLine(idUnits, nameUnits, true, error.message)), terminator: "")
        } catch let error as BoringException {
            print(decodeUnits(TestCore.resultLine(idUnits, nameUnits, true, Array(error.message.utf16))), terminator: "")
        } catch {
            let fallback = String(describing: error)
            print(decodeUnits(TestCore.resultLine(idUnits, nameUnits, true, Array(fallback.utf16))), terminator: "")
        }
        Test.currentTestId = []
    }
}

';
}
#end
