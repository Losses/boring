// expect: V03 Reflection
import std.Console;

class Case {
    static function main():Void {
        final present = Reflect.hasField({name: "a"}, "name");
        Console.log(Std.string(present));
    }
}
