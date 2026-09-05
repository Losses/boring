package tests;

import boring.GlyphCluster;
import boring.GlyphClusterHolder;
import boring.GlyphClusterReader;
import std.ReadOnlyArray;
import std.Test;

/** ReadOnlyArray element member access on a data-class record. */
class GlyphClusterTests {
    @:test("a data-class member reads off a ReadOnlyArray field element")
    public static function firstRange():Void {
        final holder = new GlyphClusterHolder([
            new GlyphCluster(3, 0, 4),
            new GlyphCluster(7, 4, 8)
        ]);
        Test.equals(3, GlyphClusterReader.firstRange(holder));
    }

    @:test("a data-class member reads off a ReadOnlyArray return element")
    public static function firstReturnedRange():Void {
        Test.equals(3, GlyphClusterReader.firstReturnedRange());
    }
}