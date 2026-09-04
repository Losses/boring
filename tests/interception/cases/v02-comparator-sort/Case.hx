// expect: V02 FunctionalIteration
class Case {
    static function main():Void {
        final items = new Array<Int>();
        items.sort(function(left:Int, right:Int):Int {
            return left - right;
        });
    }
}
