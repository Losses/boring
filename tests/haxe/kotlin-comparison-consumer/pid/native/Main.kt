import pid.Inner2
import pid.Pair2
import pid.comparePair2

fun main() {
    val intOrder = { left: Int, right: Int -> left.compareTo(right) }
    check(comparePair2(Pair2(1, Inner2(2)), Pair2(2, Inner2(1)), intOrder) < 0)
    check(comparePair2(Pair2(2, Inner2(1)), Pair2(1, Inner2(2)), intOrder) > 0)
    check(comparePair2(Pair2(1, Inner2(1)), Pair2(1, Inner2(2)), intOrder) < 0)
    check(comparePair2(Pair2(1, Inner2(2)), Pair2(1, Inner2(1)), intOrder) > 0)
    println("identity=first-then-inner")
}

fun check(condition:Boolean) {
    if (!condition) throw IllegalStateException("Check failed.")
}
