package lpc;

/**
    Authored source cases for the local presence facts.

    Every case is an ordinary static function. A call to `use` marks a read
    the checker records; its argument is the observed expression. The
    expectations live in `Checker` and were written from the source rules,
    never from the analyzer's answers.
**/
class Cases {
    /** The observation marker. It is never called at runtime. */
    public static function use<T>(v:T) {}

    /** A call of unknown result: no producer rule states its presence. */
    public static function load():Null<String> {
        return null;
    }

    public static function checked(v:Bool):Bool {
        return v;
    }

    /** A call whose result the analysis cannot know. */
    public static function probe():Bool {
        return false;
    }

    /** A call that may run a captured writer and returns a usable value. */
    public static function mutate(run:Void->Void):String {
        run();
        return "d";
    }

    /** The same call at a scalar result type, for a compound assignment. */
    public static function widen(run:Void->Void):Int {
        run();
        return 1;
    }

    // C1: a guard inside a branch that can be skipped.
    public static function skippableGuard(flag:Bool) {
        var s:Null<String> = load();
        if (flag) {
            if (s != null) {
                use(s);
            }
        }
        use(s);
    }

    // C2: a guard inside a loop body, read after the loop.
    public static function loopGuardAfterLoop(count:Int) {
        var s:Null<String> = load();
        var i = 0;
        while (i < count) {
            if (s != null) {
                use(s);
            }
            i += 1;
        }
        use(s);
    }

    // C3: a guard establishes facts for the current iteration.
    public static function loopGuardSameIteration(count:Int) {
        var s:Null<String> = load();
        var i = 0;
        while (i < count) {
            if (s == null) {
                s = "d";
            }
            use(s);
            i += 1;
        }
    }

    // C4: a loop write after a guarded use; the compared read starts unknown.
    public static function loopWriteAfterGuard(count:Int) {
        var s:Null<String> = null;
        var i = 0;
        while (i < count) {
            if (s != null) {
                use(s);
                s = load();
            }
            i += 1;
        }
        use(s);
    }

    // C5: a comparison inside call arguments refines nothing.
    public static function callArgumentComparison(d:Null<String>) {
        if (checked(d != null)) {
            use(d);
        }
    }

    // C6: a nullable assignment after a guard.
    public static function assignmentAfterGuard() {
        var s:Null<String> = load();
        if (s != null) {
            use(s);
        }
        s = load();
        use(s);
    }

    // C7: two reachable arms write different values.
    public static function joinedArms(flag:Bool) {
        var s:Null<String> = load();
        if (flag) {
            s = "a";
        } else {
            s = "b";
        }
        use(s);
    }

    // C8: a writing right operand of a short-circuit condition.
    public static function writingRightOperand() {
        var s:Null<String> = load();
        var t:Null<String> = load();
        if (s != null && (t = "d") != null) {
            use(s);
            use(t);
        }
    }

    // C9: a call that may run a closure which assigns the binding.
    public static function captureWriteThroughCall(flag:Bool) {
        var s:Null<String> = load();
        var f:Void->Void = null;
        if (flag) {
            f = function() {
                s = null;
            };
        }
        if (s != null) {
            use(s);
        }
        f();
        use(s);
    }

    // C10: a nullable field behind a present root.
    public static function fieldBehindPresentRoot(x:Holder) {
        if (x != null) {
            use(x.name);
        }
    }

    // C11: a protected region whose writes the handler cannot assume.
    public static function tryRegionAssignment() {
        var a:Null<String> = load();
        try {
            a = load();
            use(a);
            a = "d";
            use(a);
        } catch (failure:String) {}
        use(a);
    }

    // C12: a return inside the guard removes that path from the join.
    public static function returnInsideGuard(s:Null<String>) {
        if (s != null) {
            if (s.length == 0) {
                return;
            }
            use(s);
        }
        use(s);
    }

    // C13: a nested body over a capture the enclosing tree assigns.
    public static function nestedOverMutableCapture() {
        var s:Null<String> = load();
        var f:Void->Void = function() {
            use(s);
        };
        s = "d";
        use(s);
    }

    // C14: a nested body over a capture the enclosing tree never writes.
    public static function nestedOverImmutableCapture() {
        var s:Null<String> = load();
        if (s != null) {
            var f:Void->Void = function() {
                use(s);
            };
        }
    }

    // C15: producer rules and the facts a local read transfers. The
    // operands name a parameter so the typer cannot fold the operation away.
    public static function producers(count:Int, suffix:String) {
        var built:Array<Int> = [1, 2];
        var made = new Holder();
        var text = "a" + suffix;
        use(built);
        use(made);
        use(text);
        use(1 + count);
        use(load());
        use("d");
        use(count == 0);
    }

    // C16: an explicit null through a non-null annotation.
    public static function explicitNullThroughAnnotation() {
        var s:String = null;
        use(s);
    }

    // C17: two present values with different producers join to present.
    public static function joinedPresentValues(flag:Bool, suffix:String) {
        var other = "b" + suffix;
        use(flag ? "a" : other);
    }

    // C18: an arm that throws contributes no environment.
    public static function throwingArm(flag:Bool) {
        var s:Null<String> = load();
        if (flag) {
            throw "no value";
        } else {
            s = "d";
        }
        use(s);
    }

    // C19: a test that cannot hold leaves the after-loop read unreachable.
    public static function unreachableTail() {
        var s:Null<String> = load();
        while (true) {
            return;
        }
        use(s);
    }

    // C20: a post-tested loop runs its body first.
    public static function postTestedLoop(count:Int) {
        var s:Null<String> = load();
        var i = 0;
        do {
            use(s);
            i += 1;
        } while (i < count);
        use(s);
    }

    // C21: a nested assignment to null wins over an earlier guard.
    public static function nestedWriteAbsent(s:Null<String>) {
        if (s != null) {
            var t = (s = null);
            use(t);
            use(s);
        }
    }

    // C22: a false left operand skips the right operand's write.
    public static function shortCircuitSkipsWrite(flag:Bool) {
        var t:Null<String> = load();
        if (flag && (t = "d") != null) {}
        use(t);
    }

    // C23: a true left operand skips the right operand's write.
    public static function orSkipsWrite(flag:Bool) {
        var t:Null<String> = load();
        if (flag || (t = "d") != null) {}
        use(t);
    }

    // C24: the right operand reads under the left operand's true exit.
    public static function guardedRightOperandRead(s:Null<String>) {
        if (s != null && checked(s.length == 0)) {
            use(s);
        }
    }

    // C25: a literal arm and a guarded arm join to present.
    public static function literalAndGuardJoin(s:Null<String>, flag:Bool) {
        if (flag) {
            s = "d";
        } else {
            if (s == null) {
                s = "e";
            }
        }
        use(s);
    }

    // C26: an indexed read states no construction presence.
    public static function indexedRead() {
        var a:Array<Null<String>> = [null, "d"];
        use(a);
        use(a[0]);
    }

    // C27: a call in a condition keeps the throw edge and the normal path.
    public static function conditionCallThrow(s:Null<String>) {
        if (probe()) {
            use(s);
        }
    }

    // C28: a return keeps its own destination beside the normal path.
    public static function returnEdge(flag:Bool) {
        var s:Null<String> = load();
        if (flag) {
            return;
        }
        use(s);
    }

    // C29: a repeated abstract test application keeps its occurrence query.
    public static function loopTestSubject() {
        var s:Null<String> = load();
        while (s != null) {
            use(s);
            s = load();
        }
        use(s);
    }

    // C30: a closure created while present, with a later enclosing write.
    public static function closureAfterWrite() {
        var s:Null<String> = load();
        if (s != null) {
            var f:Void->Void = function() {
                use(s);
            };
            s = null;
            use(s);
        }
    }

    // C32: a left operand that cannot hold skips the right operand's write.
    public static function falseLeftSkipsRight() {
        var s:Null<String> = "d";
        if (false && (s = null) != null) {}
        use(s);
    }

    // C33: a left operand that always holds skips the right operand's write.
    public static function trueLeftSkipsRight() {
        var s:Null<String> = load();
        if (s != null) {
            if (true || (s = null) != null) {}
            use(s);
        }
    }

    // C34: a Boolean value carries the join of both reachable normal
    // outcomes. The typer keeps both comparisons over the same local.
    public static function booleanValueJoin(x:Null<String>) {
        var y = x != null && x != null;
        use(x);
    }

    // C36: a protected body that only returns leaves its catch unreachable.
    public static function returnOnlyTry(s:Null<String>) {
        try {
            return;
        } catch (failure:String) {
            s = "d";
        }
        use(s);
    }

    // C38: the or-value join keeps both reachable outcomes.
    public static function booleanOrValueJoin(x:Null<String>) {
        var y = x == null || x == null;
        use(x);
    }

    // C39: an assignment keeps the right side's effects. The writer the right
    // side may run assigns the captured local null, so the compared read right
    // after the assignment cannot still see that local as present.
    public static function assignmentKeepsRightEffects() {
        var out:Null<String> = "d";
        var side:Null<String> = "d";
        var f:Void->Void = function() {
            side = null;
        };
        out = mutate(f);
        if (side == null) {
            use(side);
        }
        use(out);
    }

    // C40: a compound assignment keeps the right side's effects under the same
    // rule.
    public static function compoundAssignmentKeepsRightEffects(count:Int) {
        var out = count;
        var side:Null<String> = "d";
        var f:Void->Void = function() {
            side = null;
        };
        out += widen(f);
        if (side == null) {
            use(side);
        }
        use(out);
    }

    // C31: a throwing operand keeps the normal path of the statement.
    public static function operandThrowKeepsNormal(flag:Bool) {
        var s:Null<String> = load();
        var f:Void->Void = null;
        if (flag) {
            f = function() {
                throw "no value";
            };
        }
        if (flag) {
            f();
        }
        use(s);
    }
}

class Holder {
    public var name:Null<String>;

    public function new() {
        name = null;
    }
}
