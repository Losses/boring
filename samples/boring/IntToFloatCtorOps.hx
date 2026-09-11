package boring;

#if swift_output
import boring.ValueTypeOps.Ic;

/**
    An Int argument to a Float-represented value type: Haxe unifies Int
    with Float and inserts a transparent cast, but Swift needs the
    explicit conversion at the constructor.
*/
class IntToFloatCtorOps {
    public static function fromInt(value:Int):Float {
        final v:Ic = new Ic(value);
        return v.toPx(1.0);
    }
}
#else
class IntToFloatCtorOps {}
#end
