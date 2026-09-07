/**
    Declaration-site nullable narrowing: a non-null local bound from an
    initializer that renders nullable (a field read off a nullable receiver,
    or a nullable arm of a ternary). Kotlin infers the local as nullable
    unless the declaration extracts once; the generator appends `!!` so that
    later member accesses use a plain dot.
*/

package boring;

class KnullInitNarrowing {
    public function new() {}

    /** Reads a field off a nullable receiver returned by a null check. */
    public function fieldOffNullableReceiver(nested:Null<Nested>):Int {
        final bound = nested;
        return bound.value;
    }

    /** Binds a non-null local from a ternary whose else arm is nullable. */
    public function ternaryWithNullableArm(flag:Bool, fallback:Null<Nested>):Int {
        final bound = flag ? new Nested(1) : fallback;
        return bound.value;
    }

    /** Chains two field accesses off a nullable receiver. */
    public function chainedFieldAccess(nested:Null<Nested>):String {
        final bound = nested;
        return bound.name;
    }
}

class Nested {
    public final value:Int;
    public final name:String;

    public function new(value:Int) {
        this.value = value;
        this.name = "v" + Std.string(value);
    }
}
