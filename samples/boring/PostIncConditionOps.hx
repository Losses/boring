package boring;

#if swift_output
/**
    A post-increment used as an expression lowers to an immediately
    invoked closure. At the head of an `if` condition Swift reads the
    opening `{` as the start of the body, so the condition needs its own
    parentheses.
*/
class PostIncConditionOps {
    public static function label(value:Int):String {
        var seen = 0;
        if (seen++ > 0) {
            return "positive";
        }
        return "first:" + seen;
    }

    public static function countTo(limit:Int):Int {
        var index = 0;
        var total = 0;
        while (index++ < limit) {
            total += 1;
        }
        return total;
    }
}
#else
class PostIncConditionOps {}
#end
