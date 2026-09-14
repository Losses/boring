package tests;

import boring.NodeFsBorrowOps;
import std.Test;

class NodeFsBorrowOpsTests {
    @:test("a node:fs extern borrows its String arguments")
    public static function writeProbe():Void {
        #if rust_output
        final path = NodeFsBorrowOps.writeProbe("probe", "probe");
        Test.equals("target/boring-node-fs-probe", path);
        #end
    }
}
