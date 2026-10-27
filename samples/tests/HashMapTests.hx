package tests;

import std.Test;
import std.HashMap;
import boring.HashMapOps;

class HashMapTests {
    @:test("dictionary set/get/exists/remove/clear lifecycle")
    public static function testLifecycle():Void {
        final d:HashMap<String, Int> = new HashMap();
        Test.equals(true, d.exists("a") == false);
        d.set("a", 1);
        Test.equals(true, d.exists("a"));
        Test.equals(true, d.get("a") == 1);
        d.set("a", 2);
        Test.equals(true, d.get("a") == 2);
        Test.equals(true, d.remove("a"));
        Test.equals(true, d.exists("a") == false);
        Test.equals(true, d.remove("a") == false);
        d.set("b", 3);
        d.clear();
        Test.equals(true, d.exists("b") == false);
        d.set("c", 4);
        Test.equals(true, d.get("c") == 4);
        Test.equals(true, HashMapOps.buildGet() == 42);
        Test.equals(true, HashMapOps.overwrite() == 2);
        Test.equals(true, HashMapOps.removeKey());
        Test.equals(true, HashMapOps.clearAndReinsert() == 3);
        Test.equals(true, HashMapOps.structuralKey() == 42);
        Test.equals(true, HashMapOps.arrayRemove());
    }

    @:test("dictionary Std.string structured emission")
    public static function testToString():Void {
        Test.equals(true, HashMapOps.directString() == "{}");
        Test.equals(true, HashMapOps.dictToString() == "DictRecord(table={})");
    }
}
