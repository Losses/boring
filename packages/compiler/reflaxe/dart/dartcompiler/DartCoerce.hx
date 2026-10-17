package dartcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Expr.Position;
import LoweredValue.Lowered;
import LoweredValue.Presence;
import Destination.Destination;
import Destination.DestinationRole;
import EmitSink;

/**
    Dart-side single conversion entry (mirrors KotlinCoerce / SwiftCoerce).
    Phase-1 foundation: the coerce entry exists and is type-checked. Phase 2
    wires requiredValueText / requiredValueTextOf (the central "!" emission
    for required value uses) through it; the remaining inline "!" sites and
    the dead-null-aware sites follow in later phases.

    Dart's null assertion is the postfix "!", exactly like Swift's, so the
    per-role conversion mirrors SwiftCoerce: Argument, Receiver,
    ArithmeticOperand and StringConcatArgument parenthesise a non-bare value
    before appending so the postfix binds to the whole expression; Assignment
    appends "!" directly and keeps the historical endsWith sniff so a value
    that already force-unwraps is not double-unwrapped.
**/
class DartCoerce {
    /** Forwarding entry; requiredValueText / requiredValueTextOf call it. */
    public static function coerce(value:Lowered, dest:Destination):String {
        var out = value.text;
        final role = Type.enumConstructor(dest.role);
        final presence = Type.enumConstructor(value.presence);
        // GP-ABLATE: a role ablation skips the whole coercion for this
        // destination role, so the site renders bare and dart analyze reports
        // the missing unwrap.
        switch (ablate()) {
            case Role(r) if (Type.enumConstructor(r) == Type.enumConstructor(dest.role)):
                if (presence == "MaybeAbsent" && !dest.admitsAbsence)
                    EmitSink.recordCoerce(value.pos, role, presence, dest.admitsAbsence, null);
                return out;
            case _:
        }
        switch (dest.role) {
            case Argument(_):
                // A narrowed non-local (field access, call, index, cast) must
                // parenthesise before ! so the postfix binds to the whole
                // expression; a bare local appends ! directly. Mirrors the
                // requiredValueText emission this role serves, and
                // KotlinCoerce.Argument's isAtomicAppendTarget.
                switch (value.presence) {
                    case MaybeAbsent if (!dest.admitsAbsence):
                        out = isBareLocal(out) ? (out + "!") : ("(" + out + ")!");
                        EmitSink.recordCoerce(value.pos, role, presence, dest.admitsAbsence, "!");
                    case _:
                }
            case Assignment(_):
                // Assignment keeps the historical endsWith sniff so a value that
                // already force-unwraps is not double-unwrapped.
                switch (value.presence) {
                    case MaybeAbsent if (!dest.admitsAbsence && !StringTools.endsWith(out, "!")):
                        out = out + "!";
                        EmitSink.recordCoerce(value.pos, role, presence, dest.admitsAbsence, "!");
                    case _:
                }
            case Receiver(_) | ArithmeticOperand | StringConcatArgument:
                // A narrowed non-local (field access, call, index, cast) must
                // parenthesise before ! so the postfix binds to the whole
                // expression; a bare local appends ! directly.
                switch (value.presence) {
                    case MaybeAbsent if (!dest.admitsAbsence && !StringTools.endsWith(out, "!")):
                        out = isBareLocal(out) ? (out + "!") : ("(" + out + ")!");
                        EmitSink.recordCoerce(value.pos, role, presence, dest.admitsAbsence, "!");
                    case _:
                }
            case _:
        }
        return out;
    }

    /**
        A lowered text that is a bare Dart identifier accepts a postfix "!"
        directly; any other expression needs parens so the postfix applies to
        the whole value.
    **/
    static function isBareLocal(text:String):Bool {
        return ~/^[A-Za-z_][A-Za-z0-9_]*$/.match(text);
    }

    public static function ablate():DartCoerceAblate {
        final raw = Context.definedValue("dart_coerce_ablate");
        final role = parseAblateRole(raw);
        if (role != null) return Role(role);
        return None;
    }

    /** GP-ABLATE role name to a DestinationRole; null when unrecognised. */
    static function parseAblateRole(raw:Null<String>):Null<DestinationRole> {
        return switch (raw) {
            case "Argument": Argument("");
            case "Assignment": Assignment("");
            case "Receiver": Receiver("");
            case "ArithmeticOperand": ArithmeticOperand;
            case "StringConcatArgument": StringConcatArgument;
            case "Condition": Condition;
            case "RangeBound": RangeBound;
            case "Discard": Discard;
            case _: null;
        };
    }
}

/** GP-ABLATE: Role(role) ablates one destination role. */
enum DartCoerceAblate {
    None;
    Role(role:DestinationRole);
}
#end
