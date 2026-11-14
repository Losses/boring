package deadlocalwrite;

/**
    Dead-local write-guard probe for the Dart target.

    Each writer declares a local with an initializer, writes it afterwards and
    never reads it. The emitter must keep the declaration: the write names the
    variable, and dart rejects a tree whose write target was never declared
    (undefined_identifier, observed downstream as "Setter not found").

    deadDeclaration is the positive control for the elimination itself: a local
    that is neither read nor written is still dropped. The ablate arm
    (-D dart_dead_local_ablate=WriteGuard) disables the write guard and leaves
    the write without its declaration (GP-ABLATE).
**/
class WriteOnlyLocal {
    /** Declaration, then a write inside a loop, then no read. */
    public static function writeInLoop(seed:Int):Int {
        var gs = seed;
        var n = 0;
        while (n < 3) {
            gs = n;
            n++;
        }
        return n;
    }

    /** Declaration, then a write inside a closure body, then no read. */
    public static function writeInClosure(seed:Int):Int {
        var gs = seed;
        final bump = () -> {
            gs = seed + 1;
        };
        bump();
        return seed;
    }

    /** Positive control: no read and no write, so the declaration is dropped. */
    public static function deadDeclaration():Int {
        var unused = 7;
        return 0;
    }
}
