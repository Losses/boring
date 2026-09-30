// Kotlin native harness. The runner copies this file into the
// generated tree root as CharCodeAtRun.kt, compiles it with the
// generated package and runtime modules (excluding runtime/test), and
// runs the jar. The text() parameter is Any? so the harness compiles
// whether the generated codeInt() signature is Int or Int?; a null
// value is rendered as the token "null".
fun main() {
    fun text(v: Any?): String = if (v == null) "null" else v.toString()
    println("subRev=" + charcodeat.CharCodeAtOracle.subRev())
    println("subHigh=" + charcodeat.CharCodeAtOracle.subHigh())
    println("subNeg=" + charcodeat.CharCodeAtOracle.subNeg())
    println("codeNull=" + text(charcodeat.CharCodeAtOracle.codeNull()))
    println("codeNeg=" + text(charcodeat.CharCodeAtOracle.codeNeg()))
    println("codeInt=" + text(charcodeat.CharCodeAtOracle.codeInt()))
}
