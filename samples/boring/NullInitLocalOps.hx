package boring;

#if swift_output
class NullInitBox {
    public final value:Int;

    public function new(value:Int) {
        this.value = value;
    }
}

/**
 * Locals declared with a plain class type and bound to a bare nil. The
 * Swift declaration names the optional type, since a bare nil carries no
 * context for the inferred type. The shape is Swift-side: the other
 * targets lower nil-bound class locals through their own option carrier.
 */
class NullInitLocalOps {
    public static function pick(boxes:Array<NullInitBox>, expected:Int):Int {
        var found:NullInitBox = null;
        for (i in 0...boxes.length) {
            if (boxes[i].value == expected) {
                found = boxes[i];
            }
        }
        return found.value;
    }

    public static function label(boxes:Array<NullInitBox>, expected:Int):String {
        var chosen:NullInitBox = null;
        for (i in 0...boxes.length) {
            if (boxes[i].value == expected) {
                chosen = boxes[i];
            }
        }
        return "v" + chosen.value;
    }
}
#else
class NullInitLocalOps {}
#end
