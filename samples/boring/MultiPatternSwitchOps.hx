package boring;

#if swift_output
enum MultiPatternKind {
    Alpha;
    Beta;
    Gamma;
}

enum MultiPatternTag {
    Left(v:Int);
    Right(v:Int);
    None;
}

/**
    A Haxe switch arm may list several patterns with `|`. The typed AST
    keeps them in one case entry, so the Swift lowering must emit one
    `case` label per pattern; dropping the later patterns makes the
    native switch non-exhaustive (and changes the answer).
*/
class MultiPatternSwitchOps {
    public static function label(kind:MultiPatternKind):String {
        return switch (kind) {
            case Alpha | Beta: "ab";
            case Gamma: "g";
        };
    }

    public static function tagValue(tag:MultiPatternTag):Int {
        return switch (tag) {
            case Left(v) | Right(v): v;
            case None: 0;
        };
    }
}
#else
class MultiPatternSwitchOps {}
#end
