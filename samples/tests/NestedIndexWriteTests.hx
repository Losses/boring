package tests;

import boring.NestedIndexWriteOps;
import std.Test;

class NestedIndexWriteTests {
    @:test("nested index write depth 2 reaches storage")
    public static function testWriteDepth2():Void {
        #if (rust_output || kotlin_output || ts_output)
        final grid = NestedIndexWriteOps.writeDepth2();
        Test.equals(2, grid.length);
        Test.equals(20, grid[0][1]);
        Test.equals(1, grid[0][0]);
        Test.equals(3, grid[1][0]);
        Test.equals(4, grid[1][1]);
        #end
    }

    @:test("nested index write depth 3 reaches storage")
    public static function testWriteDepth3():Void {
        #if (rust_output || kotlin_output || ts_output)
        final cube = NestedIndexWriteOps.writeDepth3();
        Test.equals(30, cube[0][1][0]);
        Test.equals(2, cube[0][0][1]);
        #end
    }

    @:test("nested index field write depth 2 reaches storage")
    public static function testWriteFieldDepth2():Void {
        #if (rust_output || kotlin_output || ts_output)
        final grid = NestedIndexWriteOps.writeFieldDepth2();
        Test.equals(20, grid[0][1]);
        #end
    }

    @:test("nested index field write depth 3 reaches storage")
    public static function testWriteFieldDepth3():Void {
        #if (rust_output || kotlin_output || ts_output)
        final cube = NestedIndexWriteOps.writeFieldDepth3();
        Test.equals(40, cube[1][0][1]);
        #end
    }

    @:test("nested index read depth 2")
    public static function testReadDepth2():Void {
        #if (rust_output || kotlin_output || ts_output)
        Test.equals(2, NestedIndexWriteOps.readDepth2());
        #end
    }

    @:test("nested index read depth 3")
    public static function testReadDepth3():Void {
        #if (rust_output || kotlin_output || ts_output)
        Test.equals(6, NestedIndexWriteOps.readDepth3());
        #end
    }

    @:test("nullable nested index write depth 2")
    public static function testWriteNullableDepth2():Void {
        #if (rust_output || kotlin_output || ts_output)
        final grid = NestedIndexWriteOps.writeNullableDepth2();
        Test.equals(20, grid[0][1]);
        #end
    }

    @:test("nullable field nested index write depth 2")
    public static function testWriteNullableFieldDepth2():Void {
        #if (rust_output || kotlin_output || ts_output)
        final grid = NestedIndexWriteOps.writeNullableFieldDepth2();
        Test.equals(20, grid[0][1]);
        #end
    }

    @:test("mutate referent through nested index reaches storage")
    public static function testMutateElementDepth2():Void {
        #if (rust_output || kotlin_output || ts_output)
        final grid = NestedIndexWriteOps.mutateElementDepth2();
        Test.equals("b!", grid[0][1]);
        Test.equals("a", grid[0][0]);
        #end
    }

    @:test("alias observes a nested index write")
    public static function testAliasObservesWrite():Void {
        #if (rust_output || kotlin_output || ts_output)
        Test.equals(20, NestedIndexWriteOps.aliasObservesWrite());
        #end
    }

    @:test("side-effecting nested index is evaluated once")
    public static function testSideEffectingIndex():Void {
        #if (rust_output || kotlin_output || ts_output)
        final grid = NestedIndexWriteOps.sideEffectingIndex();
        Test.equals(20, grid[0][1]);
        #end
    }

    @:test("value container of handles: writing a handle reaches the slot")
    public static function testWriteHandleContainer():Void {
        #if (rust_output || kotlin_output || ts_output)
        Test.equals(20, NestedIndexWriteOps.writeHandleContainer());
        #end
    }

    @:test("mutating a handle element reaches the shared referent")
    public static function testMutateHandleElement():Void {
        #if (rust_output || kotlin_output || ts_output)
        Test.equals(20, NestedIndexWriteOps.mutateHandleElement());
        #end
    }
}
