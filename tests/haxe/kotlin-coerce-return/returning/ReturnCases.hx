package returning;

/**
    Return coercion probe for P2.7.

    A returned value that must satisfy a non-null return-type contract is
    hardened with !!. The destination admitsAbsence follows the current
    function/lambda return type (the P1 rebound type), so:

      * inside a Null<String>-returning lambda the return <nullable> stays
        bare (the lambda's own return type is nullable, admitsAbsence),
      * the outer non-null String return hardens the nullable call with !!.

    The positive tree emits a bare return inside the lambda and an outer
    return f()!!; kotlinc accepts it. The ablate arm (-D
    kotlin_coerce_ablate=Return) drops the outer !!, leaving a bare nullable
    return so kotlinc fails (GP-ABLATE).
**/
class ReturnCases {
    public function new() {}

    /** The nullable source used by both returns. */
    public function nullableString():Null<String> {
        return null;
    }

    /** Lambda returns Null<String>; outer returns non-null String. */
    public function lambdaReturn():String {
        final f:Void->Null<String> = function():Null<String> {
            return nullableString();
        };
        return f();
    }
}
