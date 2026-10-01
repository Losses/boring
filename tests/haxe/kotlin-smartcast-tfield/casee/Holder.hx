package casee;

/**
    The field is `final` (a Kotlin `val`), so the *field* half of Kotlin's
    smart-cast requirement holds. Only the receiver half can fail here.
**/
class Holder {
    public final value:Null<Vec>;

    public function new(value:Null<Vec>) {
        this.value = value;
    }
}
