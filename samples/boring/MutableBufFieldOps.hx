package boring;

#if swift_output
import std.StringBuf;
import std.UStringException;

/**
    A `final StringBuf` field renders as a mutable unit array, so the
    field needs a `var` binding even though Haxe marks it final. An
    `Array.insert(pos, x)` call names the position with `at:`.
*/
class MutableBufFieldOps {
    public final buf:StringBuf;

    public function new() {
        this.buf = new StringBuf();
    }

    public function append(text:String):Void {
        try {
            this.buf.add(text);
            this.buf.add("\n");
        } catch (e:UStringException) {}
    }

    public function length():Int {
        return this.buf.length;
    }
}

class ArrayInsertOps {
    public static function insertAt(values:Array<Int>, pos:Int, value:Int):String {
        values.insert(pos, value);
        return values.join(",");
    }
}
#else
class MutableBufFieldOps {}
class ArrayInsertOps {}
#end
