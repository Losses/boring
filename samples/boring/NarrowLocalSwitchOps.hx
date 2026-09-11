package boring;

#if swift_output
enum NarrowLocalKind {
    Alpha;
    Beta;
    Gamma;
}

/**
    A null guard narrows a nullable enum parameter; binding it to a local
    must force-unwrap so the resumed switch is exhaustive (an optional
    subject needs a `.none` arm Swift does not have).
*/
class NarrowLocalSwitchOps {
    public static function label(kind:Null<NarrowLocalKind>):String {
        if (kind == null)
            return "none";
        final value:NarrowLocalKind = kind;
        return switch (value) {
            case Alpha: "a";
            case Beta: "b";
            case Gamma: "g";
        };
    }
}
#else
class NarrowLocalSwitchOps {}
#end
