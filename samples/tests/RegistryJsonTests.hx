package tests;
import registry.Json.Json;
import registry.Json.JsonValue;
import std.Test;
class RegistryJsonTests {
 @:test("JSON preserves escaped nested values and formatting")
 public static function roundTrip():Void {
  var value=Json.read('{"text":"a\\n\\\"b","nested":[1,2.5,true,null]}');
  Test.equals('{\n  "text": "a\\n\\\"b",\n  "nested": [\n    1,\n    2.5,\n    true,\n    null\n  ]\n}\n',Json.write(value));
 }
}
