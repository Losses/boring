package boring;

#if swift_output
/**
 * Swift arrays lack the Haxe Array member names for copy/concat/pop/
 * shift/unshift/splice/indexOf; the emitter lowers each onto the native
 * Swift form.
 */
class ArrayMethodSwiftOps {
    public static function locate(values:Array<Int>, needle:Int):Int {
        return values.indexOf(needle);
    }

    public static function findText(values:Array<String>, needle:String):Bool {
        return values.indexOf(needle) >= 0;
    }

    public static function duplicate(values:Array<Int>):Array<Int> {
        return values.copy();
    }

    public static function merge(a:Array<Int>, b:Array<Int>):Array<Int> {
        return a.concat(b);
    }

    public static function dropLast(values:Array<Int>):Int {
        final out = values.copy();
        final last = out.pop();
        return last == null ? -1 : last;
    }

    public static function dropFirst(values:Array<Int>):Int {
        final out = values.copy();
        final first = out.shift();
        return first == null ? -1 : first;
    }

    public static function prepend(values:Array<Int>, value:Int):Int {
        final out = values.copy();
        out.unshift(value);
        return out[0];
    }

    public static function cutAt(values:Array<Int>, position:Int):Array<Int> {
        final out = values.copy();
        return out.splice(position, 1);
    }
}
#else
class ArrayMethodSwiftOps {}
#end
