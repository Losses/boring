#if (macro || reflaxe_runtime)
import SourceLocalPresenceAnalysis.SourcePresence;
import SourceLocalPresenceAnalysis.SourcePresenceReason;

/** One immutable environment of local facts. */
class SourceEnvironment {
    final facts:Map<Int, SourcePresence>;

    function new(facts:Map<Int, SourcePresence>) {
        this.facts = facts;
    }

    public static function empty():SourceEnvironment {
        return new SourceEnvironment(new Map<Int, SourcePresence>());
    }

    public function fact(binding:Int):SourcePresence {
        final found = facts.get(binding);
        return found == null ? SourcePresence.Unknown : found;
    }

    public function with(binding:Int, presence:SourcePresence):SourceEnvironment {
        final next = copy();
        next.set(binding, presence);
        return new SourceEnvironment(next);
    }

    /** Sets every listed binding to `Unknown`: the loop pre-removal. */
    public function clearFacts(bindings:Array<Int>):SourceEnvironment {
        final next = copy();
        for (binding in bindings)
            next.set(binding, SourcePresence.Unknown);
        return new SourceEnvironment(next);
    }

    /** Removes the bindings a leaving block declared. */
    public function dropScope(bindings:Array<Int>):SourceEnvironment {
        if (bindings.length == 0)
            return this;
        final next = new Map<Int, SourcePresence>();
        for (key in facts.keys()) {
            var keep = true;
            for (binding in bindings)
                if (binding == key)
                    keep = false;
            if (keep)
                next.set(key, facts.get(key));
        }
        return new SourceEnvironment(next);
    }

    public function snapshot():Map<Int, SourcePresence> {
        return copy();
    }

    function copy():Map<Int, SourcePresence> {
        final next = new Map<Int, SourcePresence>();
        for (key in facts.keys())
            next.set(key, facts.get(key));
        return next;
    }

    /**
        Joins the environments of reachable paths only. Presence joins
        independently from its explanation, and a fact one path carries and
        the other does not joins to `Unknown`.
    **/
    public static function join(a:Null<SourceEnvironment>, b:Null<SourceEnvironment>):Null<SourceEnvironment> {
        if (a == null)
            return b;
        if (b == null)
            return a;
        final out = new Map<Int, SourcePresence>();
        for (key in a.facts.keys())
            out.set(key, SourcePresence.Unknown);
        for (key in b.facts.keys())
            out.set(key, SourcePresence.Unknown);
        for (key in out.keys()) {
            final left = a.facts.get(key);
            final right = b.facts.get(key);
            out.set(key, left == null || right == null ? SourcePresence.Unknown : joinPresence(left, right));
        }
        return new SourceEnvironment(out);
    }

    public static function joinAll(list:Array<SourceEnvironment>):Null<SourceEnvironment> {
        var out:Null<SourceEnvironment> = null;
        for (entry in list)
            out = join(out, entry);
        return out;
    }

    public static function joinPresence(a:SourcePresence, b:SourcePresence):SourcePresence {
        return switch [a, b] {
            case [Present(x), Present(y)]:
                sameReason(x, y) ? Present(x) : SourcePresence.Present(SourcePresenceReason.JoinedPresent);
            case [Absent(x), Absent(y)]:
                sameReason(x, y) ? Absent(x) : SourcePresence.Absent(SourcePresenceReason.JoinedAbsent);
            case _: SourcePresence.Unknown;
        }
    }

    public static function samePresence(left:SourcePresence, right:SourcePresence):Bool {
        return switch [left, right] {
            case [Unknown, Unknown]: true;
            case [Present(l), Present(r)] | [Absent(l), Absent(r)]: sameReason(l, r);
            case _: false;
        }
    }

    static function sameReason(left:SourcePresenceReason, right:SourcePresenceReason):Bool {
        return switch [left, right] {
            case [ProducerRule(l), ProducerRule(r)]: l == r;
            case [GuardPresentOutcome(l), GuardPresentOutcome(r)]
                | [GuardAbsentOutcome(l), GuardAbsentOutcome(r)]: l == r;
            case [NullAssignment, NullAssignment]
                | [NullLiteral, NullLiteral]
                | [JoinedPresent, JoinedPresent]
                | [JoinedAbsent, JoinedAbsent]
                | [NoReason, NoReason]: true;
            case _: false;
        }
    }
}

#end
