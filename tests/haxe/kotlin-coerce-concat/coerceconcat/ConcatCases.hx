package coerceconcat;

/**
    String-concatenation coercion probe for P2.6.

    Three operand shapes, one per method:

    * leftSafeChain -- a nullable receiver read through a safe call
      (value.label renders value?.label); the concatenation therefore
      uses ?.plus so a null receiver propagates null instead of coercing
      to the text "null".
    * rightNullable -- a plain non-null left and a nullable right; the
      right operand is the plus argument, and Kotlin's String.plus(Any?)
      renders a null argument as "null", so the plain + spelling stays.
    * bothNullable  -- a safe-call left and a nullable right; the left
      safe chain wins, so ?.plus is used again.
**/
class ConcatCases {
    /** Nullable field target: an unproven nullable receiver reads it with ?. */
    public var label:Null<String>;

    public function new() {
        this.label = null;
    }

    /** Left ?. chain -> value?.label?.plus("x"). */
    public function leftSafeChain(value:Null<ConcatCases>):Null<String> {
        return value.label + "x";
    }

    /** Right nullable -> "prefix" + s. */
    public function rightNullable(s:Null<String>):String {
        return "prefix" + s;
    }

    /** Both nullable -> value?.label?.plus(s). */
    public function bothNullable(value:Null<ConcatCases>, s:Null<String>):Null<String> {
        return value.label + s;
    }
}
