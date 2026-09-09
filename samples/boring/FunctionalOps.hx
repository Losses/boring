package boring;

using std.Functional;

/**
 * Regression sample for Lambda and std.Functional collection operations.
 */
class FunctionalOps {
    public static function lambdaSum(values:Array<Float>):Float {
        var total = 0.0;
        Lambda.iter(values, function(value:Float):Void {
            total += value;
        });
        return total;
    }

    public static function functionalSum(values:Array<Float>):Float {
        return values.sumOfFloat(function(value:Float):Float {
            return value;
        });
    }

    public static function lambdaIter(values:Array<Int>):Int {
        var total = 0;
        Lambda.iter(values, function(value:Int):Void {
            total += value;
        });
        return total;
    }

    public static function functionalForEach(values:Array<Int>):Int {
        var total = 0;
        values.forEach(function(value:Int):Void {
            total += value;
        });
        return total;
    }

    public static function verify():Bool {
        final ints = [1, 2, 3, 4];
        return lambdaSum([1.5, 2.0, 3.5]) == 7.0
            && functionalSum([1.5, 2.0, 3.5]) == 7.0
            && lambdaIter(ints) == 10
            && functionalForEach(ints) == 10;
    }
}
