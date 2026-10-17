package assigning;

/**
    Argument coercion probe for the Dart coerce guard (P4).

    callArgTexts passes a Null<Int> value into a non-null Int parameter,
    which requiredValueTextOf hardens via the Argument role. Three argument
    shapes are measured:

      * a method-call result   (callArgTexts path, "call"),
      * a nullable field read  (callArgTexts path, "field"),
      * a nullable local read  (callArgTexts path, "local").

    Each argument emits <value>! in the normal tree; Dart rejects the bare
    nullable argument. The ablate arm (-D dart_coerce_ablate=Argument) drops
    the coercion, leaving the bare value so `dart analyze` fails (GP-ABLATE).
**/
class AssignCases {
    public var nullableField:Null<Int>;

    public function new() {
        nullableField = null;
    }

    /** The nullable source used by every target. */
    public function nullableInt():Null<Int> {
        return null;
    }

    /** Non-null Int sink: every target passes a nullable into it. */
    public function consume(x:Int):Int {
        return x;
    }

    /** Argument from a method-call result. */
    public function passCall():Int {
        return consume(nullableInt());
    }

    /** Argument from a nullable field read. */
    public function passField():Int {
        return consume(this.nullableField);
    }

    /** Argument from a nullable local read. */
    public function passLocal():Int {
        var x:Null<Int> = nullableInt();
        return consume(x);
    }
}
