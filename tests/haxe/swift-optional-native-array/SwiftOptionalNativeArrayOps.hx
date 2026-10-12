/**
 * Round-2 defect regression fixture (WBS P5.3 criterion 1).
 *
 * Null<ReadOnlyArray<Int>> lowers to Swift [Int32]?, ReadOnlyArray<Int>
 * lowers to [Int32]. Passing an optional array into a non-optional array
 * context (argument, field assignment, return) must render an explicit
 * unwrap x! when the presence is unproven and the bare name x when a
 * null-guard has proven it. swiftc -c must return 0.
 */

import std.ReadOnlyArray;

class SwiftOptionalNativeArrayOps {
    /** Consume a non-optional read-only array - the presence-axis target. */
    static function consumeRequired(values:ReadOnlyArray<Int>, marker:Int):Int {
        return values[0] + marker;
    }

    /** Context 1 (argument): UNPROVEN optional passed to a required parameter. */
    public static function argumentUnproven(view:Null<ReadOnlyArray<Int>>):Int {
        return consumeRequired(view, 10);
    }

    /** Context 1 (argument): PROVEN optional passed after a null-guard. */
    public static function argumentProven(view:Null<ReadOnlyArray<Int>>):Int {
        if (view != null)
            return consumeRequired(view, 20);
        return 0;
    }

    /** Field that accepts a read-only array - the assignment target. */
    static var held:ReadOnlyArray<Int> = [];

    /** Context 2 (field): UNPROVEN optional assigned to a required field. */
    public static function fieldUnproven(view:Null<ReadOnlyArray<Int>>):Int {
        held = view;
        return held[0];
    }

    /** Context 2 (field): PROVEN optional assigned after a null-guard. */
    public static function fieldProven(view:Null<ReadOnlyArray<Int>>):Int {
        if (view != null) {
            held = view;
            return held[0];
        }
        return 0;
    }

    /** Context 3 (return): UNPROVEN optional returned as required. */
    public static function returnUnproven(view:Null<ReadOnlyArray<Int>>):ReadOnlyArray<Int> {
        return view;
    }

    /** Context 3 (return): PROVEN optional returned after a null-guard. */
    public static function returnProven(view:Null<ReadOnlyArray<Int>>):ReadOnlyArray<Int> {
        if (view != null)
            return view;
        return [];
    }

    static function main():Void {}
}
