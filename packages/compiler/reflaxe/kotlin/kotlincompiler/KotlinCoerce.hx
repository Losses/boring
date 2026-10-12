package kotlincompiler;

#if (macro || reflaxe_runtime)
import LoweredValue.Lowered;
import LoweredValue.Presence;
import Destination;
import Destination.DestinationRole;

/**
    The single conversion entry point for Kotlin lowering (I2/I3).
    Takes a lowered value and the destination it must satisfy, produces
    the correct target text. Three orthogonal axes (storage, presence,
    error); only the presence axis is implemented in P1.
**/
class KotlinCoerce {
    /**
        Convert a lowered value for its destination.

        Condition + MaybeAbsent appends ` == true` (Haxe null-falsy
        semantics: null matches false in a Haxe condition). Other roles
        pass through unchanged until their migration step.
    **/
    public static function coerce(value:Lowered, dest:Destination):String {
        var out = value.text;
        switch (dest.role) {
            case Condition:
                // presence axis
                switch (value.presence) {
                    case MaybeAbsent:
                        out = out + " == true";
                    case _:
                }
            case _:
                // storage / error axes are stubs for future migration steps
        }
        return out;
    }
}
#end

