package litcast;

/**
    Minimal shape of the P09 TestLitEdgeTests failure
    (samples/tests/TestLitEdgeTests.hx:11): a nullable field of an array
    element is compared against null and the non-null arm is a transparent
    Haxe cast. The cast drops the Null wrapper from the Haxe type
    (whole:Float), but the emitted Swift read is still the optional field,
    so the non-optional ternary must force-unwrap that arm.
*/
typedef LitCastEdge = {
    public var offset:Int;
    public var inlineStart:Null<Float>;
    public var inlineEnd:Null<Float>;
}

class LitCastOptionalOps {
    public static function edges():Array<LitCastEdge>
        return [{ offset: 10, inlineStart: 4.0, inlineEnd: null }];

    /** The failing shape: non-optional whole, arm laundered by the cast. */
    public static function pick():Float
        return edges()[0].inlineStart == null ? -1.0 : (edges()[0].inlineStart : Float);

    /** A local subject renders through the nil-merge path (?? ), not the ternary. */
    public static function pickLocal(e:LitCastEdge):Float
        return e.inlineStart == null ? -1.0 : (e.inlineStart : Float);

    /** The whole stays optional, so neither arm may unwrap. */
    public static function pickOptional():Null<Float>
        return edges()[0].inlineStart == null ? null : (edges()[0].inlineStart : Float);
}
