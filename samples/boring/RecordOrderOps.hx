package boring;

import std.RecordEq;

/**
 * A class record whose constructor parameter order differs from its field
 * declaration order (docs/specs/features/37-record-print-field-order.md).
 * The fields declare a, b, c; the constructor takes (a, c, ?b) because a
 * defaulted Haxe parameter must trail. The printed form follows field
 * declaration order on every target.
 */
@:dataClass
class RecordOrderShifted {
    public final a:Int;
    public final b:Int;
    public final c:String;

    public function new(a:Int, c:String, ?b:Int) {
        this.a = a;
        this.b = b == null ? 0 : b;
        this.c = c;
    }
}

/**
 * A class record whose constructor parameter order already agrees with its
 * field declaration order. Every target keeps its plain record shape; the
 * Kotlin data class keeps the native print.
 */
@:dataClass
class RecordOrderAligned {
    public final a:Int;
    public final b:Int;
    public final c:String;

    public function new(a:Int, b:Int, c:String) {
        this.a = a;
        this.b = b;
        this.c = c;
    }
}

/**
 * Read functions over the two record-order classes: the printed forms and
 * an equality check.
 */
class RecordOrderOps {
    public static function shiftedPrinted():String {
        return new RecordOrderShifted(1, "x", 5).toString();
    }

    public static function shiftedDefaulted():String {
        return new RecordOrderShifted(1, "x").toString();
    }

    public static function alignedPrinted():String {
        return new RecordOrderAligned(1, 5, "x").toString();
    }

    public static function shiftedEqual():Bool {
        final left = new RecordOrderShifted(1, "x", 5);
        final right = new RecordOrderShifted(1, "x", 5);
        return RecordEq.eq(left, right);
    }
}
