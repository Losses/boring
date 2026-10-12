#if (macro || reflaxe_runtime)
package;

import haxe.macro.Context;
import LoweredValue.Lowered;
import LoweredValue.Presence;
import Destination.Destination;
import Destination.DestinationRole;
import SwiftArrayBoundary.SwiftArrayOptionality;
import SwiftArrayBoundary.SwiftArrayStorage;

/**
    Swift-side single conversion entry (I2/I3). P5.3 adds the presence
    axis for array boundaries and the two-axis composition renderBoundary;
    storage-axis-only SAB refactor lands with it.
**/
class SwiftCoerce {
    /** P5.2 forwarding entry (generic sites migrate in P5.4+). */
    public static function coerce(value:Lowered, dest:Destination):String {
        return value.text;
    }

    /** Presence-axis forms for array boundaries (seven-row policy). */
    public enum abstract SwiftArrayPresenceForm(Int) {
        var Bare;
        var Map;
        var Unwrap;
        var Null;
        var Reject;
    }

    /** Storage-axis ops (element/container-level conversions only). */
    public enum abstract SwiftArrayStorageOp(Int) {
        var KeepPrepared;
        var ToReadOnlyView;
        var ToMutableArray;
        var ContextualReadOnlyEmpty;
    }

    /** Presence form from flow-aware facts (not Lowered.presence). */
    public static function arrayPresenceForm(optionality:SwiftArrayOptionality, admitsAbsence:Bool):SwiftArrayPresenceForm {
        return switch (optionality) {
            case RequiredOperand: Bare;
            case OptionalOperand if (admitsAbsence): Map;
            case OptionalOperand: Unwrap;
        };
    }

    /** Two-axis composition (byte-identical for the 8 existing strings). */
    public static function renderBoundary(form:SwiftArrayPresenceForm, op:SwiftArrayStorageOp, operand:String, elementText:Null<String>):String {
        return switch (op) {
            case KeepPrepared: form == Unwrap ? "(" + operand + "!)" : operand;
            case ToReadOnlyView: switch (form) {
                case Bare: "(" + operand + ").items";
                case Map: "(" + operand + ").map { $0.items }";
                case Unwrap: "(" + operand + "!).items";
                case _: operand;
            }
            case ToMutableArray: switch (form) {
                case Bare: operand + ".toMutableArray()";
                case Map: "(" + operand + ").map { $0.toMutableArray() }";
                case Unwrap: "(" + operand + "!).toMutableArray()";
                case _: operand;
            }
            case ContextualReadOnlyEmpty: "[" + elementText + "]()";
        };
    }

    /** GP-ABLATE: axis-name Presence is not a DestinationRole. */
    public enum abstract SwiftCoerceAblate(Int) {
        var None;
        var AxisPresence;
        var Role;
    }

    public static function ablate():SwiftCoerceAblate {
        final raw = Context.definedValue("swift_coerce_ablate");
        if (raw == "Presence") return AxisPresence;
        if (raw != null) return Role;
        return None;
    }
}
#end