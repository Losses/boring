package rusthandlefixtures;

// OR-condition countdown loop: mirrors PlanJsonNumber.addDecimal's
// while (i >= 0 || j >= 0 || carry > 0) with i--/j-- (PlanJsonNumber.hx:207).
// The countdown variables must keep the signed i32 domain so i >= 0
// turns false when the decrement wraps past zero; an unsigned u32 domain
// makes i >= 0 always true and the loop never exits.
class OrConditionCountdown {
    public static function countdownSteps(a:String, b:String):Int {
        var i = a.length - 1;
        var j = b.length - 1;
        var steps = 0;
        while (i >= 0 || j >= 0) {
            steps++;
            i--;
            j--;
        }
        return steps;
    }
}
