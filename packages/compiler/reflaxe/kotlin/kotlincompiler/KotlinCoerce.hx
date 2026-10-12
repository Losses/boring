package kotlincompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
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
            case ArithmeticOperand:
                // presence axis: an arithmetic/comparison operand that does
                // not admit absence extracts the value, so a nullable
                // subject hardens with "!!".
                switch (value.presence) {
                    case MaybeAbsent if (!dest.admitsAbsence):
                        out = isAtomicAppendTarget(out) ? out + "!!" : "(" + out + ")!!";
                    case _:
                }
            case _:
                // storage / error axes are stubs for future migration steps
        }
        return out;
    }

    /**
        Parse `-D kotlin_coerce_ablate=<Role>` (parse-only in P2.0; the
        switch carries no effect yet). Only payload-free DestinationRole
        constructors are addressable through a define; payload-bearing
        roles have no textual form and resolve to null. P2.1+ consumes
        this for GP-ABLATE.
    **/
    public static function ablateRole():Null<DestinationRole> {
        return parseAblateRole(Context.definedValue("kotlin_coerce_ablate"));
    }

    // Mirrors KotlinExpr.isAtomicAppendTarget until P3.3 collapses both (I2).
    static function isAtomicAppendTarget(text:String):Bool {
        var depth = 0;
        var i = 0;
        final n = text.length;
        while (i < n) {
            final c = text.charAt(i);
            switch (c) {
                case "(" | "[":
                    depth++;
                case ")" | "]":
                    depth--;
                    if (depth < 0)
                        return false;
                case "{" | "}":
                    return false;
                case " " | "." | "?" | "+" | "-" | "*" | "/" | "%" | "<" | ">" | "=" | "!" | "&" | "|" | "," | ":" | ";":
                    if (depth == 0)
                        return false;
                case _:
            }
            i++;
        }
        return depth == 0;
    }

    static function parseAblateRole(raw:Null<String>):Null<DestinationRole> {
        return switch (raw) {
            case "Condition": Condition;
            case "ArithmeticOperand": ArithmeticOperand;
            case "RangeBound": RangeBound;
            case "StringConcatArgument": StringConcatArgument;
            case "Discard": Discard;
            case _: null;
        }
    }
}
#end
