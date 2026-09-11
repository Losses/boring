package boring;

#if swift_output
using std.Functional;

/**
 * Collection pipelines inside a local function body survive the
 * pipeline expander; the Swift emitter then lowers std.Functional
 * sumOfFloat and forEach itself.
 */
class FunctionalLocalOps {
    public static function doubled(values:Array<Float>):Float {
        function total():Float {
            return values.sumOfFloat(function(value:Float):Float {
                return value * 2.0;
            });
        }
        return total();
    }

    public static function counted(values:Array<Int>):Int {
        function walk():Int {
            var total = 0;
            values.forEach(function(value:Int):Void {
                total += value;
            });
            return total;
        }
        return walk();
    }
}
#else
class FunctionalLocalOps {}
#end
