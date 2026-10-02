/// The two 32-bit halves of a binary64 value (stdlib/05). The halves
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

/// The resident unit-array reading of the same substr rule.
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

/// Read-only reference view over the same slots held by a TiqianArray.
public final class ReadOnlyArray<Element>: RandomAccessCollection {
    public typealias Index = Int
    private let backing: TiqianArray<Element>

    public init(_ backing: TiqianArray<Element>) { self.backing = backing }
    public convenience init() { self.init(TiqianArray<Element>()) }

    public var startIndex: Int { return backing.startIndex }
    public var endIndex: Int { return backing.endIndex }
    public func index(after i: Int) -> Int { return backing.index(after: i) }
    public func index(before i: Int) -> Int { return backing.items.index(before: i) }
    public func index(_ i: Int, offsetBy distance: Int) -> Int { return backing.items.index(i, offsetBy: distance) }
    public func distance(from start: Int, to end: Int) -> Int { return backing.items.distance(from: start, to: end) }
    public subscript(index: Int) -> Element { return backing[index] }

    public func toMutableArray() -> TiqianArray<Element> { return TiqianArray(Array(self)) }
}

extension ReadOnlyArray: Equatable where Element: Equatable {
    public static func == (lhs: ReadOnlyArray<Element>, rhs: ReadOnlyArray<Element>) -> Bool {
        return lhs.elementsEqual(rhs)
    }
}
public enum StringTools {
    public static func isSpace(_ s: [UInt16], _ pos: Int32) -> Bool {
        if Int32(s.count) == 0 || pos < 0 || pos >= Int32(s.count) {
            return false
        }
        let c: Int32? = Int32(s[Int(pos)])
        return (c)! > 8 && (c)! < 14 || c == 32
    }

    public static func ltrim(_ s: [UInt16]) -> [UInt16] {
        let l: Int32 = Int32(s.count)
        var r: Int32 = 0
        while r < l && StringTools.isSpace(s, r) {
            r += 1
        }
        return (r > 0 ? substrUnitsArray(s, r, l &- r) : s)
    }

    public static func rtrim(_ s: [UInt16]) -> [UInt16] {
        let l: Int32 = Int32(s.count)
        var r: Int32 = 0
        while r < l && StringTools.isSpace(s, l &- r &- 1) {
            r += 1
        }
        return (r > 0 ? substrUnitsArray(s, 0, l &- r) : s)
    }

    public static func lpad(_ s: [UInt16], _ c: [UInt16], _ l: Int32) -> [UInt16] {
        if Int32(c.count) <= 0 {
            return s
        }
        var buf_b = Array("".utf16)
        let remaining: Int32 = l &- Int32(s.count)
        while Int32(buf_b.count) < remaining {
            buf_b += c
        }
        buf_b += s
        return buf_b
    }

    public static func rpad(_ s: [UInt16], _ c: [UInt16], _ l: Int32) -> [UInt16] {
        if Int32(c.count) <= 0 {
            return s
        }
        var buf_b = Array("".utf16)
        buf_b += s
        let remaining: Int32 = l &- Int32(s.count)
        while Int32(buf_b.count) < remaining {
            buf_b += c
        }
        return buf_b
    }

    public static func replace(_ s: [UInt16], _ sub: [UInt16], _ by: [UInt16]) -> [UInt16] {
        return Array(TiqianArray(s.split(separator: sub.first!, omittingEmptySubsequences: false).map { Array($0) }).joined(separator: by))
    }
}

public enum UString {
    public static func count(_ s: [UInt16]) -> Int32 {
        var total: Int32 = 0
        var cursor: Int32 = 0
        let stop: Int32 = Int32(s.count)
        while cursor < stop {
            total &+= 1
            cursor = (cursor + Int32(unitCodePoint(s, cursor) > 0xFFFF ? 2 : 1))
        }
        return total
    }

    public static func at(_ s: [UInt16], _ index: Int32) -> Int32? {
        if index < 0 {
            return nil
        }
        var remaining: Int32 = index
        var cursor: Int32 = 0
        let stop: Int32 = Int32(s.count)
        while cursor < stop {
            if remaining == 0 {
                return unitCodePoint(s, cursor)
            }
            remaining &-= 1
            cursor = (cursor + Int32(unitCodePoint(s, cursor) > 0xFFFF ? 2 : 1))
        }
        return nil
    }

    public static func slice(_ s: [UInt16], _ from: Int32, _ to: Int32) -> [UInt16] {
        let total: Int32 = UString.count(s)
        var start: Int32 = (from < 0 ? 0 : from)
        if start > total {
            start = total
        }
        var stop: Int32 = (to > total ? total : to)
        if stop < 0 {
            stop = 0
        }
        if start >= stop {
            return Array("".utf16)
        }
        var ordinal: Int32 = 0
        var startCursor: Int32 = 0
        var cursor: Int32 = 0
        while ordinal < stop {
            if ordinal == start {
                startCursor = cursor
            }
            cursor = (cursor + Int32(unitCodePoint(s, cursor) > 0xFFFF ? 2 : 1))
            ordinal &+= 1
        }
        return Array(s[Int(startCursor)..<Int(cursor)])
    }

    public static func toCodePoints(_ s: [UInt16]) -> TiqianArray<Int32> {
        let out: TiqianArray<Int32> = TiqianArray<Int32>([])
        var cursor: Int32 = 0
        let stop: Int32 = Int32(s.count)
        while cursor < stop {
            out.append(unitCodePoint(s, cursor))
            cursor = (cursor + Int32(unitCodePoint(s, cursor) > 0xFFFF ? 2 : 1))
        }
        return out
    }

    public static func fromCodePoint(_ code: Int32) -> [UInt16] {
        return ((code >= 0 && code <= 1114111 && !(code >= 55296 && code <= 57343)) ? (code > 65535 ? [UInt16(55296 + ((code - 65536) >> 10)), UInt16(56320 + (code & 1023))] : [UInt16(code)]) : [UInt16(0)])
    }

    public static func fromCodePoints(_ codes: TiqianArray<Int32>) -> [UInt16] {
        var out = Array("".utf16)
        for index in stride(from: Int32(0), to: Int32(codes.count), by: 1) {
            out += ((codes[Int(index)] >= 0 && codes[Int(index)] <= 1114111 && !(codes[Int(index)] >= 55296 && codes[Int(index)] <= 57343)) ? (codes[Int(index)] > 65535 ? [UInt16(55296 + ((codes[Int(index)] - 65536) >> 10)), UInt16(56320 + (codes[Int(index)] & 1023))] : [UInt16(codes[Int(index)])]) : [UInt16(0)])
        }
        return out
    }
}

public enum SortedTable {
    public static func compareInts(_ a: Int32, _ b: Int32) -> Int32 {
        if a < b {
            return -1
        }
        if a > b {
            return 1
        }
        return 0
    }

    public static func compareStrings(_ a: [UInt16], _ b: [UInt16]) -> Int32 {
        let endA: Int32 = Int32(a.count)
        let endB: Int32 = Int32(b.count)
        var indexA: Int32 = 0
        var indexB: Int32 = 0
        while indexA < endA && indexB < endB {
            let codeA: Int32 = unitCodePoint(a, indexA)
            let codeB: Int32 = unitCodePoint(b, indexB)
            if codeA != codeB {
                if codeA >= 57344 && codeA < 65536 && codeB >= 65536 {
                    return 1
                }
                if codeB >= 57344 && codeB < 65536 && codeA >= 65536 {
                    return -1
                }
                if codeA < codeB {
                    return -1
                }
                return 1
            }
            indexA = (indexA + Int32(unitCodePoint(a, indexA) > 0xFFFF ? 2 : 1))
            indexB = (indexB + Int32(unitCodePoint(b, indexB) > 0xFFFF ? 2 : 1))
        }
        if indexA < endA {
            return 1
        }
        if indexB < endB {
            return -1
        }
        return 0
    }

    public static func mapBuilder<K, V>(_ compare: @escaping (K, K) -> Int32) -> SortedMapTableBuilder<K, V> {
        return SortedMapTableBuilder(TiqianArray<K>(), TiqianArray<V>(), compare)
    }

    public static func setBuilder<K>(_ compare: @escaping (K, K) -> Int32) -> SortedSetTableBuilder<K> {
        return SortedSetTableBuilder(TiqianArray<K>(), compare)
    }
}

public final class SortedMapTable<K, V> {
    private var keys: TiqianArray<K>

    private var values: TiqianArray<V>

    private let compare: (K, K) -> Int32

    public init(_ keys: TiqianArray<K>, _ values: TiqianArray<V>, _ compare: @escaping (K, K) -> Int32) {
        self.keys = keys
        self.values = values
        self.compare = compare
    }

    public func get(_ key: K) -> V? {
        let index: Int32 = self.locate(key)
        if index < 0 {
            return nil
        }
        return self.values[Int(index)]
    }

    public func has(_ key: K) -> Bool {
        return self.locate(key) >= 0
    }

    public func size() -> Int32 {
        return Int32(self.keys.count)
    }

    public func keyAt(_ index: Int32) -> K {
        return self.keys[Int(index)]
    }

    public func valueAt(_ index: Int32) -> V {
        return self.values[Int(index)]
    }

    public func toString() -> [UInt16] {
        var out = Array("{".utf16)
        var i: Int32 = 0
        while i < Int32(self.keys.count) {
            if i > 0 {
                out += Array(", ".utf16)
            }
            out += { let p0 = Array(String(describing: self.keys[Int(i)]).utf16); let p1 = Array("=".utf16); let p2 = Array(String(describing: self.values[Int(i)]).utf16); return p0 + p1 + p2 }()
            i &+= 1
        }
        return { let p0 = out; let p1 = Array("}".utf16); return p0 + p1 }()
    }

    private func locate(_ key: K) -> Int32 {
        var low: Int32 = 0
        var high: Int32 = Int32(self.keys.count)
        while low < high {
            let mid: Int32 = (low &+ high) >> 1
            let order: Int32 = self.compare(self.keys[Int(mid)], key)
            if order < 0 {
                low = mid &+ 1
            } else if order > 0 {
                high = mid
            } else {
                return mid
            }
        }
        return -1
    }
}

public final class SortedMapTableBuilder<K, V> {
    private var keys: TiqianArray<K>

    private var values: TiqianArray<V>

    private let compare: (K, K) -> Int32

    public init(_ keys: TiqianArray<K>, _ values: TiqianArray<V>, _ compare: @escaping (K, K) -> Int32) {
        self.keys = keys
        self.values = values
        self.compare = compare
    }

    public func put(_ key: K, _ value: V) -> Void {
        self.keys.append(key)
        self.values.append(value)
    }

    public func get(_ key: K) -> V? {
        var index: Int32 = Int32(self.keys.count)
        while index > 0 {
            index &-= 1
            if self.compare(self.keys[Int(index)], key) == 0 {
                return self.values[Int(index)]
            }
        }
        return nil
    }

    public func build() -> SortedMapTable<K, V> {
        let total: Int32 = Int32(self.keys.count)
        let order = TiqianArray<Int32>()
        var i: Int32 = 0
        while i < total {
            order.append(i)
            i &+= 1
        }
        i = 1
        while i < total {
            let current: Int32 = order[Int(i)]
            var j: Int32 = i
            var moved = true
            while j > 0 && moved {
                if self.compare(self.keys[Int(order[Int(j &- 1)])], self.keys[Int(current)]) > 0 {
                    if Int(j) < order.count { order[Int(j)] = order[Int(j &- 1)] } else { order.append(order[Int(j &- 1)]) }
                    j &-= 1
                } else {
                    moved = false
                }
            }
            if Int(j) < order.count { order[Int(j)] = current } else { order.append(current) }
            i &+= 1
        }
        let outKeys = TiqianArray<K>()
        let outValues = TiqianArray<V>()
        i = 0
        while i < total {
            var run: Int32 = i
            while run &+ 1 < total && self.compare(self.keys[Int(order[Int(run &+ 1)])], self.keys[Int(order[Int(i)])]) == 0 {
                run &+= 1
            }
            outKeys.append(self.keys[Int(order[Int(run)])])
            outValues.append(self.values[Int(order[Int(run)])])
            i = run &+ 1
        }
        return SortedMapTable(outKeys, outValues, self.compare)
    }
}

public final class SortedSetTable<K> {
    private var keys: TiqianArray<K>

    private let compare: (K, K) -> Int32

    public init(_ keys: TiqianArray<K>, _ compare: @escaping (K, K) -> Int32) {
        self.keys = keys
        self.compare = compare
    }

    public func has(_ key: K) -> Bool {
        return self.locate(key) >= 0
    }

    public func size() -> Int32 {
        return Int32(self.keys.count)
    }

    public func at(_ index: Int32) -> K {
        return self.keys[Int(index)]
    }

    public func toString() -> [UInt16] {
        var out = Array("[".utf16)
        var i: Int32 = 0
        while i < Int32(self.keys.count) {
            if i > 0 {
                out += Array(", ".utf16)
            }
            out += Array(String(describing: self.keys[Int(i)]).utf16)
            i &+= 1
        }
        return { let p0 = out; let p1 = Array("]".utf16); return p0 + p1 }()
    }

    private func locate(_ key: K) -> Int32 {
        var low: Int32 = 0
        var high: Int32 = Int32(self.keys.count)
        while low < high {
            let mid: Int32 = (low &+ high) >> 1
            let order: Int32 = self.compare(self.keys[Int(mid)], key)
            if order < 0 {
                low = mid &+ 1
            } else if order > 0 {
                high = mid
            } else {
                return mid
            }
        }
        return -1
    }
}

public final class SortedSetTableBuilder<K> {
    private var keys: TiqianArray<K>

    private let compare: (K, K) -> Int32

    public init(_ keys: TiqianArray<K>, _ compare: @escaping (K, K) -> Int32) {
        self.keys = keys
        self.compare = compare
    }

    public func put(_ key: K) -> Void {
        self.keys.append(key)
    }

    public func build() -> SortedSetTable<K> {
        let total: Int32 = Int32(self.keys.count)
        let order = TiqianArray<Int32>()
        var i: Int32 = 0
        while i < total {
            order.append(i)
            i &+= 1
        }
        i = 1
        while i < total {
            let current: Int32 = order[Int(i)]
            var j: Int32 = i
            var moved = true
            while j > 0 && moved {
                if self.compare(self.keys[Int(order[Int(j &- 1)])], self.keys[Int(current)]) > 0 {
                    if Int(j) < order.count { order[Int(j)] = order[Int(j &- 1)] } else { order.append(order[Int(j &- 1)]) }
                    j &-= 1
                } else {
                    moved = false
                }
            }
            if Int(j) < order.count { order[Int(j)] = current } else { order.append(current) }
            i &+= 1
        }
        let outKeys = TiqianArray<K>()
        i = 0
        while i < total {
            var run: Int32 = i
            while run &+ 1 < total && self.compare(self.keys[Int(order[Int(run &+ 1)])], self.keys[Int(order[Int(i)])]) == 0 {
                run &+= 1
            }
            outKeys.append(self.keys[Int(order[Int(run)])])
            i = run &+ 1
        }
        return SortedSetTable(outKeys, self.compare)
    }
}
