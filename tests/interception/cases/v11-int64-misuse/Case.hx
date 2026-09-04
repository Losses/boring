// expect: V11 Int64Misuse
import boring.Console;

class Case {
    static function main():Void {
        final text = Std.string(haxe.Int64.make(1, 2));
        Console.log(text);
    }
}
