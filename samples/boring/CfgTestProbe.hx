package boring;

import std.Test;

class CfgTestProbe {
    @:test("cfg(test) gate probe for a business-package test module")
    public static function probe():Void {
        Test.equals(1, 1);
    }
}
