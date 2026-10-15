class NullIntGuard {
    static function compute(boundary:Int, active:Bool):Int {
        var matchingTierBoundary:Null<Int> = null;
        if (active) {
            matchingTierBoundary = boundary;
        }
        if (matchingTierBoundary != null) {
            var groupEnd = matchingTierBoundary - 1;
            return groupEnd;
        }
        return 0;
    }

    static function main() {
        var r = compute(5, true);
    }
}
