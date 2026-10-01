package casee;

/**
    Same shape as Holder but the field is a Haxe `var`, i.e. a Kotlin `var`
    property. Kotlin never smart-casts a mutable property, so this exercises
    the field half of the predicate independently of the receiver half.
**/
class MutableHolder {
    public var value:Null<Vec>;

    public function new(value:Null<Vec>) {
        this.value = value;
    }
}
