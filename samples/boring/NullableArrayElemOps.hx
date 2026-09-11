package boring;

#if swift_output
/**
    An array literal whose element type is non-optional but an element
    is a nullable read: the element unwraps at the literal position.
*/
class NullableElem {
    public final n:Int;

    public function new(n:Int)
        this.n = n;
}

class NullableArrayElemOps {
    public static function make(n:Int):NullableElem
        return new NullableElem(n);

    public static function collect(v:Null<NullableElem>):Array<NullableElem>
        return [v];

    public static function count(v:Null<NullableElem>):Int
        return collect(v).length;
}
#else
class NullableArrayElemOps {}
#end
