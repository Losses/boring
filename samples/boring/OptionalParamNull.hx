package boring;

/**
 * Optional parameters with null defaults render as nullable types in
 * Kotlin. Haxe's `?param:Type` registers a VNull default; the Kotlin
 * generator must wrap the declared type as `Type?` so `= null` type-checks.
 */
class OptionalParamNull {
    public static function intDefault(?p:Int):Int {
        if (p == null) {
            return 0;
        }
        return p;
    }

    public static function classDefault(?q:SomeClass):String {
        if (q == null) {
            return new SomeClass().label;
        }
        return q.label;
    }
}

class SomeClass {
    public final label:String;

    public function new() {
        this.label = "default";
    }
}
