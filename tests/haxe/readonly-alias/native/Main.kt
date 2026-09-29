// Kotlin native harness. The runner copies this file into the generated
// tree root as ReadOnlyAliasRun.kt, compiles it with the generated
// package and runtime modules (excluding runtime/test), and runs the jar.
fun main() {
    println("alias=" + roalias.ReadOnlyAliasOracle.alias())
    println("passed=" + roalias.ReadOnlyAliasOracle.passed())
    println("escaped=" + roalias.ReadOnlyAliasOracle.escaped())
    println("rebind=" + roalias.ReadOnlyAliasOracle.rebind())
    println("boundary=" + roalias.ReadOnlyAliasOracle.boundary())
}
