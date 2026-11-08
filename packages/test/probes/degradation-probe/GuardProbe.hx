package;

#if macro
import haxe.macro.Context;

/**
 * Guard probe for the DegradedLvalueGuard place-path predicate. Runs at
 * macro time during this compilation and fails the build (nonzero RC) on
 * the first mismatched expectation. See docs/audit-degradation-granularity.md.
 *
 *   lost-write shapes (must report):
 *     (v[0]).clone().field      conversion mid-path, no deref rescue
 *     self.f.clone()            conversion is the place terminal
 *     x.to_string()             terminal conversion
 *     Array.from(RANGES)        whole-value wrapper terminal
 *     opt.unwrap()              terminal conversion
 *   place shapes (must not report):
 *     *remaining.lock().unwrap()   deref head + interior-mutability reader
 *     *c.borrow_mut()              deref head + interior-mutability reader
 *     x.field / records[0] / x     plain places
 **/
class GuardProbe {
    public static function check():Void {
        var failures = 0;
        failures += expect("*remaining.lock().unwrap()", false);
        failures += expect("*c.borrow_mut()", false);
        failures += expect("x.field", false);
        failures += expect("records[0]", false);
        failures += expect("x", false);
        failures += expect("(v[0]).clone().field", true);
        failures += expect("self.f.clone()", true);
        failures += expect("x.to_string()", true);
        failures += expect("Array.from(RANGES)", true);
        failures += expect("opt.unwrap()", true);
        if (failures > 0)
            Context.fatalError("guard probe failed: " + failures + " mismatch(es)", Context.currentPos());
        Sys.println("GUARD-PROBE-OK");
    }

    static function expect(text:String, shouldReport:Bool):Int {
        final hit = AssignTargetPlan.lvalueConversionHit(text);
        if (shouldReport && hit == null) {
            Sys.println("MISS (should report): " + text);
            return 1;
        }
        if (!shouldReport && hit != null) {
            Sys.println("FALSE-POSITIVE: " + text + " -> " + hit);
            return 1;
        }
        return 0;
    }
}
#end
