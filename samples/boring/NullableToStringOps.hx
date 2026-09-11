package boring;

#if swift_output
/**
    `Std.string` on a class value whose Haxe type is non-null but whose
    local declaration is a null literal: Haxe narrows the flow type to
    plain, while the Swift binding stays optional, so the rendered
    receiver still unwraps.
*/
class NullableInfo {
    public final code:Int;

    public function new(code:Int)
        this.code = code;

    public function toString():String
        return "info:" + code;
}

class NullableToStringOps {
    public static function make(code:Int):NullableInfo
        return new NullableInfo(code);

    public static function render(use:Bool):String {
        var hit:NullableInfo = null;
        if (use)
            hit = new NullableInfo(7);
        return hit == null ? "null" : Std.string(hit);
    }

    public static function describe(use:Bool):String {
        var hit:NullableInfo = null;
        if (use)
            hit = new NullableInfo(9);
        return hit == null ? "null" : hit.toString();
    }
}
#else
class NullableToStringOps {}
#end
