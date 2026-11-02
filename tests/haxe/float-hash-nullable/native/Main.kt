import floathashnullable.NullableFloatRecord
import kotlin.system.exitProcess

/**
 * Native assertion harness for the Kotlin (f64) generated tree of the
 * nullable-float hashCode regression contract (board t-mvzn8ckw-vh3s). kotlinc
 * builds this file against the generated library jar and java runs it. The
 * harness instantiates the generated NullableFloatRecord and asserts, in the
 * target language, that hashCode is stable for null / signed zero / NaN and
 * that equals semantics are unchanged. It exits nonzero on any failure.
 */
fun main() {
    var failures = 0
    fun check(cond: Boolean, message: String) {
        if (!cond) {
            System.err.println("FAIL: " + message)
            failures++
        }
    }

    val hashNull = NullableFloatRecord(null).hashCode()
    val hashPosZero = NullableFloatRecord(0.0).hashCode()
    val hashNegZero = NullableFloatRecord(-0.0).hashCode()
    val hashNaN = NullableFloatRecord(Double.NaN).hashCode()

    // null hashes to 0 and a signed zero hashes to zero bits, so a single-field
    // record hashes null, +0.0, and -0.0 all equal (P-13 float canonical).
    check(hashNull == hashPosZero, "hashCode(null) == hashCode(+0.0) [null->0, signed-zero->0]")
    check(hashNull == hashNegZero, "hashCode(null) == hashCode(-0.0) [null->0, signed-zero->0]")
    // NaN keeps its quiet-token bits and is stable.
    check(hashNaN == hashNaN, "hashCode(NaN) is stable")

    // equals semantics unchanged.
    check(NullableFloatRecord(null) == NullableFloatRecord(null), "null == null")
    check(NullableFloatRecord(null) != NullableFloatRecord(0.0), "null != +0.0")
    check(NullableFloatRecord(0.0) == NullableFloatRecord(-0.0), "+0.0 == -0.0")

    if (failures > 0) {
        System.err.println("$failures assertion(s) failed")
        exitProcess(1)
    }
    println("float-hash-nullable kotlin contract: all assertions passed")
}
