// expect: coalesced default expression may reference earlier parameters only
class Case {
    static function main() {
        later(1);
    }

    static function later(first:Int, ?fallback:Int, ?laterValue:Int):Int {
        var normalized = fallback == null ? laterValue : fallback;
        return normalized;
    }
}
