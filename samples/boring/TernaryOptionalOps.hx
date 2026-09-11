package boring;

#if swift_output
/**
    A ternary whose true branch is an optional value while the whole
    expression is non-optional: the branch unwraps so both arms have the
    same Swift type.
*/
class TernaryOptionalOps {
    public static function choose(high:Null<Int>, low:Null<Int>):Int {
        return low < 56320 || low > 57343 ? high : 65536 + low;
    }
}
#else
class TernaryOptionalOps {}
#end
