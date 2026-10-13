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
        // GP-ABLATE: with -D kotlin_coerce_ablate=<Role>, skip coercion for
        // the ablated role so a fixture can prove the coercion is load-bearing.
        // Byte-identical when the define is absent (ablateRole() == null).
        final ablated = ablateRole();
        if (ablated != null && Type.enumConstructor(ablated) == Type.enumConstructor(dest.role)) {
            return out;
        }
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
            case RangeBound:
                // presence axis: a range bound is an Int position, so a
                // nullable value still extracts; append "!!" directly (no
                // atomicity wrapping, so ?.size!! and f()!! stay as-is).
                switch (value.presence) {
                    case MaybeAbsent if (!dest.admitsAbsence):
                        out = out + "!!";
                    case _:
                }
            case Argument(_):
                // presence axis: an argument to a parameter that does not
                // admit absence extracts the value with "!!"; an Any?
                // parameter admits absence and passes the nullable through
                // unchanged (ConcatenationNullableArgument).
                switch (value.presence) {
                    case MaybeAbsent if (!dest.admitsAbsence):
                        out = isAtomicAppendTarget(out) ? out + "!!" : "(" + out + ")!!";
                    case _:
                }
            case Receiver(memberKind):
                switch (memberKind) {
                    case "Method":
                        // charCodeAt captures its receiver as a non-null local
                        // (_s), so a nullable receiver value extracts with "!!"
                        // and a present one passes through unchanged; the
                        // member-access operator (".", "?.") is not part of this
                        // value. (CharCodeAtReceiverExtraction)
                        switch (value.presence) {
                            case MaybeAbsent if (!dest.admitsAbsence):
                                out = isAtomicAppendTarget(out) ? out + "!!" : "(" + out + ")!!";
                            case _:
                        }
                    case _:
                        // Property / Length member access: the access operator
                        // follows the access result written by the decision
                        // site (nullableAccess) — "?." stays nullable
                        // (MaybeAbsent), "." and "!!." are present. The "!!"
                        // extraction for "!!." is embedded in the text by the
                        // decision site, not re-derived here, so the three
                        // access forms stay distinct (L6 instance two).
                        switch (value.presence) {
                            case MaybeAbsent:
                                out = out + "?.";
                            case Present:
                                out = out + ".";
                            case _:
                        }
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
                    // A bare block/lambda at depth 0 is never a postfix
                    // operand; a parenthesized block `(run { ... })` is one
                    // primary, so braces inside parens keep it atomic.
                    if (depth == 0)
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
            case "Argument": Argument("");
            case "Receiver": Receiver("");
            case "Discard": Discard;
            case _: null;
        }
    }
}
#end
