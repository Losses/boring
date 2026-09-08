package boring;

@:valueType
abstract ProbeUnit(Int) from Int {
    public inline function new(value:Int)
        this = value;

    public static final ZERO:ProbeUnit = 0;
}
