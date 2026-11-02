package floathashnullable;

/**
 * Regression fixture for the nullable-float hashCode defect (board
 * t-mvzn8ckw-vh3s). Commit 86c33fc3e added the P-13 float-canonical hashCode
 * path but did not handle nullable floats: a @:dataClass with a Null<Float>
 * field generated Float?.toBits() on Kotlin and passed a double? into
 * haxeFloatHashBits(double) on Dart, so the generated tree did not compile.
 *
 * This fixture only declares the data class and references it (dead-code
 * elimination guard). No assertion lives in Haxe source: hashCode is a
 * target-language artifact, not a Haxe member. The assertions run in the
 * native harnesses (native/Main.kt, native/main.dart) against the generated
 * class, and run.sh greps the generated artifacts for the nullable-hash
 * pattern and compiles the generated tree.
 */
@:dataClass
class NullableFloatRecord {
    public var value:Null<Float>;

    public function new(value:Null<Float>) {
        this.value = value;
    }
}

class FloatHashNullableContract {
    /** Constructs an instance with a null field (references the data class). */
    public static function makeNull():NullableFloatRecord {
        return new NullableFloatRecord(null);
    }

    /** Constructs an instance with a +0.0 field (references the data class). */
    public static function makePosZero():NullableFloatRecord {
        return new NullableFloatRecord(0.0);
    }

    /** Constructs an instance with a -0.0 field (references the data class). */
    public static function makeNegZero():NullableFloatRecord {
        return new NullableFloatRecord(-0.0);
    }

    /** Constructs an instance with a NaN field (references the data class). */
    public static function makeNaN():NullableFloatRecord {
        return new NullableFloatRecord(Math.NaN);
    }
}
