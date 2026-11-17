// Hand-written probe scaffold; the generator does not emit this file.
//
// The Swift emitter has no String -> CFString conversion: every Haxe String
// lowers to [UInt16] (packages/compiler/reflaxe/swift/swiftcompiler/SwiftType.hx:28-37),
// and no construct in the translatable subset produces a CFString from it.
// This file adds the one conversion the emitted call needs so the Core Text
// call site can stay generated. A production cutover needs the same
// conversion as a first-class emitter mechanism.
import CoreText

func coreTextString(_ units: [UInt16]) -> CFString {
    return String(decoding: units, as: UTF16.self) as CFString
}
