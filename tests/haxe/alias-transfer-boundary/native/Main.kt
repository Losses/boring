// Kotlin native harness. The runner copies this file into the generated
// tree root as AliasTransferRun.kt, compiles it with the generated
// package and runtime modules (excluding runtime/test), and runs the jar.
fun main() {
    println("field=" + atb.ContainerAliasOracle.field())
    println("fieldNull=" + atb.ContainerAliasOracle.fieldNull())
    println("fieldRebind=" + atb.ContainerAliasOracle.fieldRebind())
    println("relay=" + atb.ContainerAliasOracle.relay())
    println("relayFresh=" + atb.ContainerAliasOracle.relayFresh())
}
