#if (macro || reflaxe_runtime)
package;

import haxe.macro.Context;
import LoweredValue.Lowered;
import Destination.Destination;
import Destination.DestinationRole;

/**
    Swift-side single conversion entry (I2/I3). P5.2 is the forwarding
    skeleton: coerce returns the value text unchanged; role-specific
    axes migrate in P5.3-P5.5. Parse-only ablate switch for L5.
**/
class SwiftCoerce {
    public static function coerce(value:Lowered, dest:Destination):String {
        return value.text;
    }

    public static function ablateRole():Null<DestinationRole> {
        return parseAblateRole(Context.definedValue("swift_coerce_ablate"));
    }

    static function parseAblateRole(raw:Null<String>):Null<DestinationRole> {
        return switch (raw) {
            case null: null;
            case "Condition": Condition;
            case "ArithmeticOperand": ArithmeticOperand;
            case "RangeBound": RangeBound;
            case "StringConcatArgument": StringConcatArgument;
            case "Discard": Discard;
            case _: null; // payload-carrying roles map in P5.3+
        }
    }
}
#end