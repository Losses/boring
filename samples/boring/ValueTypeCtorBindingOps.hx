package boring;

#if swift_output
/**
    An inline wrapper constructor whose argument is a nullable field read.
    The typer binds the argument to a synthetic local of the wrapper block,
    and the representation value resolves through that binding.
**/
@:valueType
abstract Cell(Float) from Float {
    public inline function new(value:Float)
        this = value;

    public function raw():Float
        return this;
}

class ValueTypeCtorBindingOps {
    public static var seed:Null<Float> = null;

    public static function wrapped():Null<Cell>
        return seed == null ? null : new Cell(seed);

    public static function rawOrZero():Float {
        final cell = wrapped();
        return cell == null ? 0.0 : cell.raw();
    }

    public static function withSeed(value:Float):Float {
        seed = value;
        return rawOrZero();
    }
}
#else
class ValueTypeCtorBindingOps {}
#end
