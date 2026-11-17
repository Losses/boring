package probe;

/**
    The unit-array to `CFString` seam.

    Every Haxe `String` lowers to `[UInt16]` in this target
    (SwiftType.hx:28-37, StringUnitArrayBacking), so a `CFString` argument has
    no emitted spelling: there is no conversion in the subset and no cast that
    succeeds. `tests/swift-coretext-probe/swift/CoreTextStringBridge.swift`
    supplies the one-line conversion by hand; this extern names it, so the
    Core Text call itself stays generated.
**/
extern class CoreTextStringBridge {
    @:topLevel
    static function coreTextString(units:String):CFString;
}
