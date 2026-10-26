package tests;

import std.Test;
import std.Dictionary;
import boring.DictionaryOps;

class DictionaryTests {
    @:test("dictionary set/get/exists/remove/clear lifecycle")
    public static function testLifecycle():Void {
        final d:Dictionary<String, Int> = new Dictionary();
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
        Test.equals(true, DictionaryOps.buildGet() == 42);
        Test.equals(true, DictionaryOps.overwrite() == 2);
        Test.equals(true, DictionaryOps.removeKey());
        Test.equals(true, DictionaryOps.clearAndReinsert() == 3);
        Test.equals(true, DictionaryOps.structuralKey() == 42);
        Test.equals(true, DictionaryOps.arrayRemove());
    }

    @:test("dictionary Std.string structured emission")
    public static function testToString():Void {
        Test.equals(true, DictionaryOps.directString() == "{}");
        Test.equals(true, DictionaryOps.dictToString() == "DictRecord(table={})");
    }
}
