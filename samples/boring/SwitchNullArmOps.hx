package boring;

#if swift_output
enum SwitchNullTone {
    Plain;
    Rising;
    Falling;
}

/**
 * A variant switch used as a statement whose arm value is the bare null
 * constant lowers to a unit no-op; a context-free nil is not a Swift
 * expression.
 */
class SwitchNullArmOps {
    public static function label(tone:SwitchNullTone):String {
        var out = "";
        switch (tone) {
            case Plain:
                null;
            case Rising:
                out = "rising";
            case Falling:
                out = "falling";
        }
        return out;
    }
}
#else
class SwitchNullArmOps {}
#end
