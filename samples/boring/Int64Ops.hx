package boring;

import haxe.Int64;

/** Fixed-width Int64 operations shared by the target capability tests. */
class Int64Ops {
    public static function carry():Int64 {
        return Int64.make(0, -1) + Int64.ofInt(1);
    }

    public static function mulAnchors():Int64 {
        return Int64.make(0x9E3779B1, 0x85EBCA87) * Int64.make(0xC2B2AE3D, 0x27D4EB4F);
    }

    public static function mulIntAnchor(value:Int64):Int64 {
        return Int64.mul(value, 3);
    }

    public static function rotate(value:Int64, distance:Int):Int64 {
        return Int64.or(Int64.ushr(value, distance), Int64.shl(value, 64 - distance));
    }

    public static function bitMix(value:Int64):Int64 {
        final upperMask = Int64.make(0xAAAAAAAA, 0x55555555);
        final lowerMask = Int64.make(0x55555555, 0xAAAAAAAA);
        return Int64.or(Int64.xor(value, upperMask), Int64.and(value, lowerMask));
    }

    public static function high(value:Int64):Int {
        return Int64.getHigh(value);
    }

    public static function low(value:Int64):Int {
        return Int64.getLow(value);
    }

    public static function below(a:Int64, b:Int64):Bool {
        return a < b;
    }

    public static function atOrBelow(a:Int64, b:Int64):Bool {
        return a <= b;
    }
}
