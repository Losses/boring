package boring;

#if rust_output
/**
    A Float compound assignment mixes Haxe's unified numeric domain with the
    Rust operator traits. An Int right side widens to the Float target, so
    the emitted `op=` carries the same explicit cast an ordinary Float
    operand receives.
*/
class FloatCompoundAssignOps {
    public static function scaled(value:Float):Float {
        var x = value;
        while (x >= 10.0) {
            x /= 10;
        }
        while (x < 1.0) {
            x *= 10;
        }
        return x;
    }

    public static function stepTotal():Float {
        var total = 0.0;
        var i = 0;
        while (i < 3) {
            total += 1;
            i++;
        }
        return total;
    }

    public static function walk(value:Float):Float {
        var x = value;
        x += 2;
        x -= 1;
        return x;
    }
}
#else
class FloatCompoundAssignOps {}
#end
