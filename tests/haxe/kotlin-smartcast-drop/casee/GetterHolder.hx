package casee;

/**
    Getter-only probe for the `getter` clause.

    `var value(get, never)` renders as a Kotlin `val` with a custom getter
    (`val value get() = get_value()`), but at the Haxe level the field is
    `isFinal=false` because it is a `var`. The `val` clause therefore
    rejects it before the `getter` clause can run. And `final value(get,
    never)` is a Haxe *syntax error*: the grammar's final branch accepts only
    `final name [:type] [=expr]` or `final function`, never a
    property-accessor production. No field is therefore ever both final and
    getter-only, so the `getter` clause is vacuous: `drop=getter` changes
    nothing and both directions emit the same hardened `!!` and compile rc=0.
**/
class GetterHolder {
    var backing:Null<Vec>;

    public var value(get, never):Null<Vec>;

    function get_value():Null<Vec> {
        return backing;
    }

    public function new(value:Null<Vec>) {
        this.backing = value;
    }
}
