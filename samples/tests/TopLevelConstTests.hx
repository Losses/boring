package tests;

import boring.HolderConstOps;
import boring.TopLevelConstOps;
import std.Test;

/** Runtime hooks for the top-level constant form (features/10). */
class TopLevelConstTests {
    @:test("a marked static final crosses module boundaries as a module constant")
    public static function testTopLevelConsts():Void {
        Test.equals("PlatformMultiFaceStringDraw", TopLevelConstOps.PLATFORM_ISSUE);
        Test.equals(7, TopLevelConstOps.privateLimitThroughPublic());
    }

    @:test("an unmarked static final keeps its holder member")
    public static function testHolderMember():Void {
        Test.equals("HolderMember", HolderConstOps.HOLDER_ISSUE);
        Test.equals("HolderMember", new HolderConstOps(1).issue());
    }
}
