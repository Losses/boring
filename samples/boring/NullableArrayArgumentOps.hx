package boring;

#if rust_output
/**
    A nullable Array local passed to a borrowed Array parameter. The parameter
    lowers to a &Vec view while the null-checked local holds an Option<Vec>, so
    the argument unwraps the Option to its Vec view. The named nullableArrayArg
    rule covers the borrowed-array argument position.
*/
class NullableArrayArgumentOps {
    public static function sum(values:Array<Int>):Int {
        var total = 0;
        for (value in values) {
            total = total + value;
        }
        return total;
    }

    public static function checkedSum(values:Null<Array<Int>>):Int {
        if (values == null) {
            return 0;
        }
        return sum(values);
    }
}
#else
class NullableArrayArgumentOps {}
#end
