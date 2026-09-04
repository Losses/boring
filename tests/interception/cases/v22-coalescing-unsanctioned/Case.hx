// expect: coalesced default expression is not sanctioned
class Case {
    static function main() {
        invalid(1);
    }

    static function invalid(first:Int, ?fallback:Array<Int>):Int {
        var normalized = fallback == null ? [first] : fallback;
        return normalized.length;
    }
}
