package assigning;

/**
    Assignment coercion probe for P2.3.

    assignValueText (assignment statements/expressions) and the local
    declaration path both coerce a Null<Int> value to a non-null Int target
    via the Assignment role. Three targets are measured:

      * a non-null local declaration (extractAtDecl path, "local"),
      * a non-null array element write (assignValueText, "array"),
      * a non-null field write (assignValueText, "field").

    Each target emits <value>!! in the normal tree; Kotlin rejects the bare
    nullable value with "type mismatch: inferred type is Int? but Int was
    expected". The ablate arm (-D kotlin_coerce_ablate=Assignment) drops the
    coercion, leaving the bare value so kotlinc fails (GP-ABLATE).
**/
class AssignCases {
    public var field:Int;

    public function new() {
        field = 0;
    }

    /** The nullable source used by every target. */
    public function nullableInt():Null<Int> {
        return null;
    }

    /** Non-null local declaration from a nullable initializer. */
    public function assignLocal():Int {
        var x:Int = nullableInt();
        return x;
    }

    /** Non-null array element write from a nullable value. */
    public function assignArray():Int {
        var arr:Array<Int> = [0];
        arr[0] = nullableInt();
        return arr[0];
    }

    /** Non-null field write from a nullable value. */
    public function assignField():Int {
        this.field = nullableInt();
        return this.field;
    }
}
