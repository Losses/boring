package tests;

import boring.NullBoolEmphasisOps;
import boring.NullBoolStyle;
import boring.NullBoolTernaryOps;
import std.SortedMap;
import std.Test;

class NullBoolTernaryTests {
    @:test("a narrowed Null<Bool> local drives a ternary in the guarded branch")
    public static function ternaryOnNarrowedNullBool():Void {
        Test.equals("true", NullBoolTernaryOps.flagText(new NullBoolStyle(true)));
        Test.equals("false", NullBoolTernaryOps.flagText(new NullBoolStyle(false)));
        Test.equals("absent", NullBoolTernaryOps.flagText(new NullBoolStyle(null)));
        Test.equals(1, NullBoolTernaryOps.flagBit(new NullBoolStyle(true)));
        Test.equals(0, NullBoolTernaryOps.flagBit(new NullBoolStyle(false)));
        Test.equals(-1, NullBoolTernaryOps.flagBit(new NullBoolStyle(null)));
    }

    @:test("a narrowed Null<Array> local coalesces without re-wrapping")
    public static function coalescingNarrowedPayload():Void {
        Test.equals(2, NullBoolEmphasisOps.pickList(["a", "b"]));
        Test.equals(0, NullBoolEmphasisOps.pickList(null));
    }

    @:test("a coalescing ternary over a map-read narrowed local holds the payload")
    public static function coalescingMapReadPayload():Void {
        final b:SortedMapBuilder<String, Array<String>> = SortedMap.builder();
        b.put("k", ["x", "y", "z"]);
        final map = b.build();
        Test.equals(3, NullBoolEmphasisOps.lookupList(map, "k"));
        Test.equals(0, NullBoolEmphasisOps.lookupList(map, "missing"));
    }

    @:test("a non-null value fills a nullable object literal field")
    public static function nonNullIntoNullableField():Void {
        final e = NullBoolEmphasisOps.emphasize(3.0);
        Test.equals(3.0, e.clusterRangeStart == null ? -1.0 : (e.clusterRangeStart : Float));
        Test.equals(6.0, e.anchorX);
    }
}
