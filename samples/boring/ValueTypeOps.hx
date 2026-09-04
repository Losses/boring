package boring;

/**
 * The two value-wrapper shapes from the planned abstract-types
 * extension: an arithmetic Float wrapper and a validating String
 * wrapper. The members are deliberately consumed by ValueTypeConsumer
 * from another module.
 */
@:valueType
abstract Ic(Float) from Float {
    public inline function new(count:Float)
        this = count;

    inline function count():Float
        return this;

    public function toPx(emPx:Float):Float
        return this * emPx;

    @:op(A + B)
    static inline function plus(a:Ic, b:Ic):Ic
        return new Ic(a.count() + b.count());

    @:op(-A)
    static inline function negate(a:Ic):Ic
        return new Ic(-a.count());

    public static var ZERO:Ic = new Ic(0.0);
}

@:valueType
abstract FontFaceId(String) from String {
    public function new(value:String) {
        if (StringTools.trim(value) == "") {
            throw new ValueException(BlankValue);
        }
        this = value;
    }

    public function toString():String
        return this;
}
