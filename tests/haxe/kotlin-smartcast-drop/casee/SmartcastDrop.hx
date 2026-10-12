package casee;

/**
    Ablation fixture for the smart-cast clause table in
    `KotlinExpr.smartCastableSubject` (GP-ABLATE, WBS §0.3).

    `smartCastableSubject` is a conjunction of clauses, each gated by
    `-D kotlin_smartcast_drop=<clause>`. Dropping a clause re-emits the
    unhardened spelling -- the bare dot -- and kotlinc surfaces the exact
    error that clause prevents, so the fixture asserts error-text fragments,
    not just rc (see the driver).

    Clause tally:

      val           bidirectional  rc 0 vs !=0  "mutable property"
      closurewrite  bidirectional  rc 0 vs !=0  "mutated in a capturing closure"
      rebind        bidirectional  rc 0 vs !=0  "only safe (?.) ... nullable receiver"
      open          vacuous         rc 0 vs 0    (backend never emits `open`)
      getter        vacuous         rc 0 vs 0    (`var X(get,never)` is caught
                                                  by `val` first; `final
                                                  X(get,never)` is a syntax error)
      sameunit      (deferred: needs two-stage cross-module compilation)

    `valField`/`closureRebind`/`rebindBetween` are negative controls whose
    default spelling is hardened (`!!`); `stableOpen` is an over-reach control
    whose bare dot must stay; `getterOnly` is a vacuous control that stays
    hardened in both directions.
**/
class SmartcastDrop {
    /** Clause `val`: a Kotlin `var` property is never smart-castable. */
    public static function valField():Float {
        final m = new MutableHolder(new Vec(1.0));
        if (m.value != null) {
            return m.value.magnitude();
        }
        return 0.0;
    }

    /** Clause `closurewrite`: the root local is written from a capturing closure. */
    public static function closureRebind(flag:Bool):Float {
        var a = new Holder(new Vec(1.0));
        final bump:Void->Void = function() {
            a = new Holder(null);
        };
        touch(bump, flag);
        if (a.value != null) {
            return a.value.magnitude();
        }
        return 0.0;
    }

    static function touch(f:Void->Void, call:Bool):Void {
        if (call) {
            f();
        }
    }

    /** Clause `rebind`: the root local is rebound between the guard and the use. */
    public static function rebindBetween(flag:Bool):Float {
        var a = new Holder(new Vec(1.0));
        if (a.value != null) {
            if (flag) {
                a = new Holder(null);
            }
            return a.value.magnitude();
        }
        return 0.0;
    }

    /**
        Clause `open`: the backend never emits `open`, so no field is ever
        structurally `open` and the clause holds vacuously. `drop=open` is
        consulted nowhere in the emitter, so the bare dot stays and kotlinc
        accepts it -- rc=0 in both directions. This doubles as the over-reach
        control: hardening it instead would trade the error for an
        "unnecessary non-null assertion (!!)" warning.
    **/
    public static function stableOpen():Float {
        final c = new Holder(new Vec(2.0));
        if (c.value != null) {
            return c.value.magnitude();
        }
        return 0.0;
    }

    /**
        Clause `getter`: a getter-only field is always a `var`, so the
        `val` clause rejects it before `getter` can (see GetterHolder).
        `drop=getter` is therefore a no-op: the hardened `!!` stays and
        kotlinc accepts it -- rc=0 in both directions.
    **/
    public static function getterOnly():Float {
        final g = new GetterHolder(new Vec(3.0));
        if (g.value != null) {
            return g.value.magnitude();
        }
        return 0.0;
    }
}
