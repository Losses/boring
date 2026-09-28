package boring;

/**
    Minimal shape for the nullable-array-element object literal: a named
    struct typedef whose nullable field receives a non-null literal inside
    an Array<Typed> element (the PlanPackedTest inline-edge shape).
*/
typedef TestLitEdge = {
    public var offset:Int;
    public var inlineStart:Null<Float>;
    public var inlineEnd:Null<Float>;
}

class TestLitEdgeOps {
    public static function edgeList():Array<TestLitEdge> {
        final edges:Array<TestLitEdge> = [{ offset: 10, inlineStart: 4.0, inlineEnd: null }];
        return edges;
    }

    public static function directReturn():TestLitEdge {
        return { offset: 20, inlineStart: 8.0, inlineEnd: null };
    }
}
