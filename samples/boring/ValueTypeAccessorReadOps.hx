package boring;

#if (swift_output || dart_output || kotlin_output || rust_output)
import boring.ValueTypeAccessorFace;

/**
    Reads the wrapper's inline representation accessor in the positions that
    demand the representation: an argument, a return, an initializer, and a
    factory result.
**/
class ValueTypeAccessorReadOps {
    static function label(value:String):String
        return "[" + value + "]";

    /** Initializer from a borrowed String, then a read. */
    public static function initializeFrom(variable:String):String {
        final face = new ValueTypeAccessorFace(variable);
        final copy = face.value;
        return copy;
    }

    /** Argument position: the inlined read unboxes into the local, then the
        local reaches the String parameter. */
    public static function passArgumentFrom(variable:String):String {
        final face = ValueTypeAccessorFace.of(variable);
        final text = face.value;
        return label(text);
    }

    /** Return position. */
    public static function returnFrom(variable:String):String {
        final face = ValueTypeAccessorFace.of(variable);
        return face.value;
    }

    /** Factory result read through the declared accessor. */
    public static function factoryRead(variable:String):String {
        final face = ValueTypeAccessorFace.of(variable);
        return face.value;
    }
}
#else
class ValueTypeAccessorReadOps {}
#end
