package tests;

import boring.BorrowedIterationSubjectOps;
import std.Test;

class BorrowedIterationSubjectOpsTests {
    @:test("an element loop borrows an already-referenced subject once")
    public static function unique():Void {
        #if rust_output
        final values = [3, 1, 3, 2, 1];
        Test.equals("3,1,2", BorrowedIterationSubjectOps.unique(values).join(","), "parameter");
        Test.equals("3,1,2", BorrowedIterationSubjectOps.uniqueNullable(values).join(","), "nullable");
        Test.equals("3,1,2", BorrowedIterationSubjectOps.uniqueThroughLocal(values).join(","), "local");
        #end
    }
}
