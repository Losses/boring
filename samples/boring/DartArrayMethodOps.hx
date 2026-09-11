package boring;

#if dart_output
/**
 * Haxe Array members Dart's List names differently (concat, splice,
 * reverse, unshift, pop, shift) lower onto the equivalent List
 * operation, and a bool comparison condition emits no toDouble call.
 */
class DartArrayMethodOps {
    public static function merge(a:Array<Int>, b:Array<Int>):Array<Int> {
        return a.concat(b);
    }

    public static function cutAt(values:Array<Int>, position:Int):Array<Int> {
        return values.splice(position, 1);
    }

    public static function flipped(values:Array<Int>):Array<Int> {
        values.reverse();
        return values;
    }

    public static function prepended(values:Array<Int>, value:Int):Int {
        values.unshift(value);
        return values[0];
    }

    public static function last(values:Array<Int>):Null<Int> {
        return values.pop();
    }

    public static function first(values:Array<Int>):Null<Int> {
        return values.shift();
    }

    public static function emptyOrNegative(count:Int, width:Float):Bool {
        return count == 0 || width <= 0.0;
    }
}
#else
class DartArrayMethodOps {}
#end
