package kotlincompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import LoweredValue.Lowered;
import LoweredValue.Presence;
import Destination;
import Destination.DestinationRole;
import EmitSink;

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
        final role = Type.enumConstructor(dest.role);
        final presence = Type.enumConstructor(value.presence);
        // GP-ABLATE: with -D kotlin_coerce_ablate=<Role>, skip coercion for
        // the ablated role so a fixture can prove the coercion is load-bearing.
        // Byte-identical when the define is absent (ablateRole() == null).
        // Match by constructor tag so a payload-bearing role such as
        // Assignment(target) still ablates no matter which target was recorded.
        final ablated = ablateRole();
        if (ablated != null && roleTag(ablated) == roleTag(dest.role)) {
            return out;
        }
        switch (dest.role) {
            case Condition:
                // presence axis
                switch (value.presence) {
                    case MaybeAbsent:
                        out = out + " == true";
                        EmitSink.recordCoerce(value.pos, role, presence, dest.admitsAbsence, "== true");
                    case _:
                }
            case ArithmeticOperand:
                // presence axis: an arithmetic/comparison operand that does
                // not admit absence extracts the value, so a nullable
                // subject hardens with "!!".
                switch (value.presence) {
                    case MaybeAbsent if (!dest.admitsAbsence):
                        out = isAtomicAppendTarget(out) ? out + "!!" : "(" + out + ")!!";
                        EmitSink.recordCoerce(value.pos, role, presence, dest.admitsAbsence, "!!");
                    case _:
                }
            case RangeBound:
                // presence axis: a range bound is an Int position, so a
                // nullable value still extracts; append "!!" directly (no
                // atomicity wrapping, so ?.size!! and f()!! stay as-is).
                switch (value.presence) {
                    case MaybeAbsent if (!dest.admitsAbsence):
                        out = out + "!!";
                        EmitSink.recordCoerce(value.pos, role, presence, dest.admitsAbsence, "!!");
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
                        EmitSink.recordCoerce(value.pos, role, presence, dest.admitsAbsence, "!!");
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
                                EmitSink.recordCoerce(value.pos, role, presence, dest.admitsAbsence, "!!");
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
                                EmitSink.recordCoerce(value.pos, role, presence, dest.admitsAbsence, "?.");
                            case Present:
                                out = out + ".";
                                EmitSink.recordCoerce(value.pos, role, presence, dest.admitsAbsence, ".");
                            case _:
                        }
                }
            case Assignment(_):
                // presence axis: assigning a nullable value to a non-null
                // target (local/array element/field) extracts it. Same
                // atomicity-shaped harden as ArithmeticOperand so that an
                // embedded expression like `a + b` wraps before "!!".
                switch (value.presence) {
                    case MaybeAbsent if (!dest.admitsAbsence):
                        out = isAtomicAppendTarget(out) ? out + "!!" : "(" + out + ")!!";
                        EmitSink.recordCoerce(value.pos, role, presence, dest.admitsAbsence, "!!");
                    case _:
                }
            case StringConcatArgument:
                // presence axis: the caller encoded "needs !!" into presence
                // (a null-initialized non-null Haxe value extracts; a
                // nullable Haxe type and a safe-call chain pass through, so
                // Kotlin's String?.plus renders a null as the text "null").
                switch (value.presence) {
                    case MaybeAbsent:
                        out = isAtomicAppendTarget(out) ? out + "!!" : "(" + out + ")!!";
                        EmitSink.recordCoerce(value.pos, role, presence, dest.admitsAbsence, "!!");
                    case _:
                }
            case Return(_):
                // presence axis: a returned value that must satisfy a non-null
                // return-type contract extracts with "!!". Same atomicity-shaped
                // harden as Argument/Assignment so an embedded expression like
                // "a + b" wraps before "!!".
                switch (value.presence) {
                    case MaybeAbsent if (!dest.admitsAbsence):
                        out = isAtomicAppendTarget(out) ? out + "!!" : "(" + out + ")!!";
                        EmitSink.recordCoerce(value.pos, role, presence, dest.admitsAbsence, "!!");
                    case _:
                }
            case _:
                // storage / error axes are stubs for future migration steps
        }
        return out;
    }

    /**
        Parse `-D kotlin_coerce_ablate=<Role>` into the role whose coercion
        GP-ABLATE skips. Payload-bearing roles are addressed by constructor
        name only, so their payload is filled with a placeholder (see
        roleTag / parseAblateRole).
    **/
    public static function ablateRole():Null<DestinationRole> {
        return parseAblateRole(Context.definedValue("kotlin_coerce_ablate"));
    }

    // Mirrors KotlinExpr.isAtomicAppendTarget until P3.3 collapses both (I2).
    // P2.7: a lone "." is member access and stays atomic (x.field!!); only a
    // ".." range is non-atomic. Other divergences from the reference (e.g.
    // braces inside parens stay atomic) are preserved for byte-identity.
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
                    // operand; a parenthesized block (run { ... }) is one
                    // primary, so braces inside parens keep it atomic.
                    if (depth == 0)
                        return false;
                case ".":
                    // Member access is atomic; only ".." (range) is not.
                    if (depth == 0 && i + 1 < n && text.charAt(i + 1) == ".")
                        return false;
                case " " | "?" | "+" | "-" | "*" | "/" | "%" | "<" | ">" | "=" | "!" | "&" | "|" | "," | ":" | ";":
                    if (depth == 0)
                        return false;
                case _:
            }
            i++;
        }
        return depth == 0;
    }

    // Compares roles by constructor name so payload-bearing constructors
    // (Receiver/Argument/Assignment/Return) still match for ablation.
    static function roleTag(role:DestinationRole):String {
        return switch (role) {
            case Condition: "Condition";
            case ArithmeticOperand: "ArithmeticOperand";
            case RangeBound: "RangeBound";
            case Receiver(_): "Receiver";
            case Argument(_): "Argument";
            case Assignment(_): "Assignment";
            case Return(_): "Return";
            case StringConcatArgument: "StringConcatArgument";
            case Discard: "Discard";
        };
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
            case "Assignment": Assignment("");
            case "Return": Return("");
            case _: null;
        }
    }
}
#end
