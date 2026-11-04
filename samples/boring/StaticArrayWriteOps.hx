package boring;

/**
    A static final array subscript write must fail before generation: the
    staticStorage declaration (Immutable for a final array) rejects it.
    (PlacePolicy negative control)
**/
class StaticArrayWriteOps {
    public function new() {}

    static final STATIC_ARR:Array<Array<Int>> = [[1, 2], [3, 4]];

    public static function writeStaticArray():Array<Array<Int>> {
        STATIC_ARR[0][1] = 9;
        return STATIC_ARR;
    }
}
