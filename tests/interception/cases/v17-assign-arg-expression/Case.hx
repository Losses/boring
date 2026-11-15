// expect: V17 AssignArgExpression
import std.Console;

class Case {
    static function helper(keep:Bool):Void {
        Console.log(Std.string(keep));
    }

    static function main():Void {
        helper(keep = true);
    }
}
