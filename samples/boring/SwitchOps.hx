package boring;

enum SwitchMark {
    Empty;
    Number(value:Int);
    Text(value:String);
    Other;
}

/**
 * Variant-switch lowering fixtures covering statement assignment, initializer,
 * default arms, and payload captures for TypeScript and Swift.
 */
class SwitchOps {
    /** Statement position: each arm assigns an already-declared local. */
    public static function statement(mark:SwitchMark):String {
        var value:String = "unset";
        switch (mark) {
            case Empty: value = "empty";
            case Number(n): value = "number:" + n;
            case Text(s): value = "text:" + s;
            case Other: value = "other";
        }
        return value;
    }

    /** Initializer position: the switch itself initializes a local. */
    public static function initializer(mark:SwitchMark):String {
        final value = switch (mark) {
            case Empty: "empty";
            case Number(n): "number:" + n;
            case Text(s): "text:" + s;
            case Other: "other";
        };
        return value;
    }

    /** Default arm: an unmatched variant uses the fallback value. */
    public static function defaulted(mark:SwitchMark):String {
        var value:String = "unset";
        switch (mark) {
            case Empty: value = "empty";
            case Number(_): value = "number";
            case Text(_): value = "text";
            case Other: value = "fallback";
        }
        return value;
    }
}
