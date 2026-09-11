package tests;

import std.Test;

#if swift_output
import boring.InterfaceFieldRecordOps;
#end

class InterfaceFieldRecordTests {
    @:test("a record with an interface field drops the unsynthesizable Equatable")
    public static function testInterfaceField():Void {
        #if swift_output
        final record = InterfaceFieldRecordOps.make("tone");
        Test.equals("tone", record.label);
        Test.equals("tone:mark", InterfaceFieldRecordOps.describe(record));
        #else
        Test.equals(true, true);
        #end
    }
}
