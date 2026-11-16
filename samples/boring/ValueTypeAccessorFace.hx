package boring;

#if (swift_output || dart_output || kotlin_output || rust_output)
/**
    A value wrapper whose inline representation accessor returns `this`. Haxe
    lowers a read to an unboxing cast, so the read has to name the stored
    representation at the positions that demand it. The samples had inline
    members that return `this`, but no read of one.
**/
@:valueType
@:mainOnly
abstract ValueTypeAccessorFace(String) {
    public inline function new(value:String)
        this = value;

    public static function of(value:String):ValueTypeAccessorFace
        return new ValueTypeAccessorFace(value);

    inline function get_value():String
        return this;

    public var value(get, never):String;

    public function toString():String
        return this;
}
#else
class ValueTypeAccessorFace {}
#end
