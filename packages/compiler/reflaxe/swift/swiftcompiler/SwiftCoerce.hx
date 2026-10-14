package swiftcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Expr.Position;
import LoweredValue.Lowered;
import LoweredValue.Presence;
import Destination.Destination;
import Destination.DestinationRole;
import swiftcompiler.SwiftArrayBoundary.SwiftArrayOptionality;
import swiftcompiler.SwiftArrayBoundary.SwiftArrayStorageOp;
import swiftcompiler.SwiftArrayBoundary.SwiftArrayPresenceFact;
import swiftcompiler.SwiftArrayBoundary.SwiftArrayBoundaryPlan;
import EmitSink;

/**
    Swift-side single conversion entry (I2/I3). P5.3 adds the presence
    axis for array boundaries and the two-axis composition renderBoundary;
    the storage-axis-only SAB refactor lands with it.
**/
class SwiftCoerce {
    /** P5.2 forwarding entry (generic sites migrate in P5.4+). */
    public static function coerce(value:Lowered, dest:Destination):String {
        var out = value.text;
        final role = Type.enumConstructor(dest.role);
        final presence = Type.enumConstructor(value.presence);
        // GP-ABLATE: a role ablation skips the whole coercion for this
        // destination role, so the site renders bare and swiftc reports the
        // missing unwrap.
        switch (ablate()) {
            case Role(r) if (Type.enumConstructor(r) == Type.enumConstructor(dest.role)):
                if (presence == "MaybeAbsent" && !dest.admitsAbsence)
                    EmitSink.recordCoerce(value.pos, role, presence, dest.admitsAbsence, null);
                return out;
            case _:
        }
        switch (dest.role) {
            case Argument(_):
                // Argument sites never sniff the rendered text: a parenthesized
                // optional must still gain !.
                switch (value.presence) {
                    case MaybeAbsent if (!dest.admitsAbsence):
                        out = out + "!";
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
        A lowered text that is a bare Swift identifier (optionally backticked)
        accepts a postfix `!` directly; any other expression needs parens so
        the postfix applies to the whole value.
    **/
    static function isBareLocal(text:String):Bool {
        return ~/^[A-Za-z_][A-Za-z0-9_]*$/.match(text) || ~/^`[A-Za-z_][A-Za-z0-9_]*`$/.match(text);
    }

    /**
        Presence form from flow-aware facts (not Lowered.presence). A
        RequiredOperand is bare only when its Swift binding is already plain;
        a guard-proven nullable keeps its optional Swift type, so the axis
        force-unwraps it instead of dropping to a bare name.
    **/
    public static function arrayPresenceForm(optionality:SwiftArrayOptionality, presenceFact:SwiftArrayPresenceFact,
            admitsAbsence:Bool):SwiftArrayPresenceForm {
        return switch (optionality) {
            case RequiredOperand if (presenceFact == GuardProvenPresent): ForceUnwrap;
            case RequiredOperand: Bare;
            case OptionalOperand if (admitsAbsence): Map;
            case OptionalOperand: Unwrap;
        };
    }

    /** Two-axis composition (byte-identical for the existing storage ops). */
    public static function renderBoundary(form:SwiftArrayPresenceForm, op:SwiftArrayStorageOp, operand:String, elementText:Null<String>):String {
        return switch (op) {
            case KeepPrepared: switch (form) {
                case Unwrap: "(" + operand + "!)";
                case ForceUnwrap: operand + "!";
                case Bare | Map | Null | Reject: operand;
            }
            case ToReadOnlyView: switch (form) {
                case Bare: "ReadOnlyArray(" + operand + ")";
                case Map: "(" + operand + ").map { ReadOnlyArray($0) }";
                case Unwrap: "ReadOnlyArray(" + operand + "!)";
                case ForceUnwrap: "ReadOnlyArray(" + operand + "!)";
                case Null | Reject: operand;
            }
            case ToMutableArray: switch (form) {
                case Bare: operand + ".toMutableArray()";
                case Map: "(" + operand + ").map { $0.toMutableArray() }";
                case Unwrap: "(" + operand + "!).toMutableArray()";
                case ForceUnwrap: operand + "!.toMutableArray()";
                case Null | Reject: operand;
            }
            case ContextualReadOnlyEmpty: "ReadOnlyArray<" + elementText + ">()";
        };
    }

    /**
        Compose the presence axis over the storage plan for one array boundary.
        The ablated presence axis passes the operand through with its source
        optionality. Returns the rendered text and the presence-derived result
        optionality for downstream joins.
    **/
    public static function coerceArrayBoundary(operand:String, pos:Null<Position>, dest:Destination, optionality:SwiftArrayOptionality,
            plan:SwiftArrayBoundaryPlan, elementText:Null<String>):{text:String, optionality:SwiftArrayOptionality} {
        switch (ablate()) {
            case AxisPresence:
                if (optionality == OptionalOperand && !dest.admitsAbsence)
                    EmitSink.recordCoerce(pos, Type.enumConstructor(dest.role), "MaybeAbsent", false, null);
                return { text: operand, optionality: optionality };
            case Role(r) if (Type.enumConstructor(r) == Type.enumConstructor(dest.role)):
                if (optionality == OptionalOperand && !dest.admitsAbsence)
                    EmitSink.recordCoerce(pos, Type.enumConstructor(dest.role), "MaybeAbsent", false, null);
                return { text: operand, optionality: optionality };
            case _:
        }
        final form = arrayPresenceForm(optionality, plan.presenceFact, dest.admitsAbsence);
        return {
            text: renderBoundary(form, plan.operation, operand, elementText),
            optionality: resultOptionality(form)
        };
    }

    /** Presence form to result optionality (Map|Null stay optional; the rest are required). */
    static function resultOptionality(form:SwiftArrayPresenceForm):SwiftArrayOptionality {
        return switch (form) {
            case Map | Null: OptionalOperand;
            case Bare | Unwrap | ForceUnwrap | Reject: RequiredOperand;
        };
    }

    public static function ablate():SwiftCoerceAblate {
        final raw = Context.definedValue("swift_coerce_ablate");
        if (raw == "Presence") return AxisPresence;
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

/** Presence-axis forms for array boundaries (seven-row policy). */
enum SwiftArrayPresenceForm {
    Bare;
    Map;
    Unwrap;
    ForceUnwrap;
    Null;
    Reject;
}

/** GP-ABLATE: Presence ablates the presence axis; Role(role) ablates one destination role. */
enum SwiftCoerceAblate {
    None;
    AxisPresence;
    Role(role:DestinationRole);
}
#end
