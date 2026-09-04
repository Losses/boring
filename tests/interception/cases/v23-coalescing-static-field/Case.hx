// expect: coalesced default expression is not sanctioned
class Case {
    static function main() {
        invalid(1);
    }

    static inline var Factor:Int = 2;

    static function invalid(first:Int, ?fallback:Int):Int {
        var normalized = fallback == null ? Factor + [first].length : fallback;
        return normalized + first;
    }
}
