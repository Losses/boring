package deadlocalwrite;

/**
    Dead-local write-guard probe for the Dart target.

    writePure declares a local, writes it inside a loop and never reads it: the
    declaration and the write are both dead, so the emitter drops the whole
    binding. writeEffectTopLevel writes it with a side-effecting value at
    statement position: the assignment goes and the call survives as an
    expression statement. writeInClosure writes it inside a closure body, which
    the write pass cannot rewrite, so the declaration stays as the safe net.

    deadDeclaration is the positive control for the elimination itself: a local
    that is neither read nor written is still dropped. The ablate arm
    (-D dart_dead_local_ablate=WriteGuard) disables the write pass and leaves
    every declaration dropped with its writes in place (GP-ABLATE).
**/
class WriteOnlyLocal {
    static var calls:Int = 0;

    static function sideEffect(seed:Int):Int {
        calls++;
        return seed + 1;
    }

    /** Declaration + pure write in a loop + never read: the binding goes. */
    public static function writePure(seed:Int):Int {
        var gs = seed;
        var n = 0;
        while (n < 3) {
            gs = n;
            n++;
        }
        return n;
    }

    /** Declaration + statement-position side-effecting write: the call stays. */
    public static function writeEffectTopLevel(seed:Int):Int {
        var gs = seed;
        gs = sideEffect(seed);
        return calls;
    }

    /** Declaration + write in a closure body: the declaration stays. */
    public static function writeInClosure(seed:Int):Int {
        var gs = seed;
        final bump = () -> {
            gs = sideEffect(seed);
        };
        bump();
        return calls;
    }

    /** Positive control: no read and no write, so the declaration is dropped. */
    public static function deadDeclaration():Int {
        var unused = 7;
        return 0;
    }
}
