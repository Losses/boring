package swiftcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import LoweredValue.Lowered;
import Destination.Destination;
import swiftcompiler.SwiftArrayBoundary.SwiftArrayOptionality;
import swiftcompiler.SwiftArrayBoundary.SwiftArrayStorageOp;
import swiftcompiler.SwiftArrayBoundary.SwiftArrayPresenceFact;
import swiftcompiler.SwiftArrayBoundary.SwiftArrayBoundaryPlan;

/**
    Swift-side single conversion entry (I2/I3). P5.3 adds the presence
    axis for array boundaries and the two-axis composition renderBoundary;
    the storage-axis-only SAB refactor lands with it.
**/
class SwiftCoerce {
    /** P5.2 forwarding entry (generic sites migrate in P5.4+). */
    public static function coerce(value:Lowered, dest:Destination):String {
        return value.text;
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
                case Bare: "(" + operand + ").items";
                case Map: "(" + operand + ").map { $0.items }";
                case Unwrap: "(" + operand + "!).items";
                case ForceUnwrap: "(" + operand + "!).items";
                case Null | Reject: operand;
            }
            case ToMutableArray: switch (form) {
                case Bare: operand + ".toMutableArray()";
                case Map: "(" + operand + ").map { $0.toMutableArray() }";
                case Unwrap: "(" + operand + "!).toMutableArray()";
                case ForceUnwrap: operand + "!.toMutableArray()";
                case Null | Reject: operand;
            }
            case ContextualReadOnlyEmpty: "[" + elementText + "]()";
        };
    }

    /**
        Compose the presence axis over the storage plan for one array boundary.
        The ablated presence axis passes the operand through with its source
        optionality. Returns the rendered text and the presence-derived result
        optionality for downstream joins.
    **/
    public static function coerceArrayBoundary(operand:String, dest:Destination, optionality:SwiftArrayOptionality,
            plan:SwiftArrayBoundaryPlan, elementText:Null<String>):{text:String, optionality:SwiftArrayOptionality} {
        if (ablate() == AxisPresence)
            return { text: operand, optionality: optionality };
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
        if (raw != null) return Role;
        return None;
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

/** GP-ABLATE: axis-name Presence is not a DestinationRole. */
enum SwiftCoerceAblate {
    None;
    AxisPresence;
    Role;
}
#end
