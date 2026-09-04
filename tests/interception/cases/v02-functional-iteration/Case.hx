// expect: V02 FunctionalIteration
import boring.Console;

class Case {
    static function main():Void {
        final items = new Array<Int>();
        final sum = items.reduce(function(acc:Int, item:Int):Int {
            return acc + item;
        });
        Console.log(Std.string(sum));
    }
}
