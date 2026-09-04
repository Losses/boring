// expect: V14 DynamicCatch
import boring.Console;

class Case {
    static function main():Void {
        try {
            final value = 1;
            Console.log(Std.string(value));
        } catch (error:Dynamic) {
            Console.log("caught");
        }
    }
}
