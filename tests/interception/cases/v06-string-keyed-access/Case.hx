// expect: V06 StringKeyedAccess
import std.Console;

class Case {
    static function main():Void {
        final record = {name: "a"};
        final value = record["name"];
        Console.log(value);
    }
}
