package tests;

import boring.NullInflatedLiteralOps;
import std.Test;

class NullInflatedLiteralOpsTests {
    @:test("a Null-inflated object literal lowers against its named typedef")
    public static function record():Void {
        #if (rust_output || kotlin_output)
        final known = NullInflatedLiteralOps.record("known");
        Test.equals("known", known.label);
        Test.equals("d", known.detail != null ? known.detail : "missing");
        Test.equals(1.0, known.weight != null ? known.weight : -1.0);
        final void = NullInflatedLiteralOps.record("void");
        Test.equals("void", void.label);
        Test.equals("absent", void.detail != null ? void.detail : "absent");
        Test.equals(-1.0, void.weight != null ? void.weight : -1.0);
        #end
    }
}
