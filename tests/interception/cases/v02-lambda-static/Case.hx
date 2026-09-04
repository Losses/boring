// expect: V02 FunctionalIteration
import boring.Console;

class Case {
    static function main():Void {
        final items = new Array<Int>();
        final total = Lambda.fold(items, function(item:Int, acc:Int):Int {
            return acc + item;
        }, 0);
        Console.log(Std.string(total));
    }
}
