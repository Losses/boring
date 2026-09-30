// Kotlin native harness. The runner copies this file into the generated
// tree root as TryTailRun.kt and compiles it with the generated modules.
import trytail.TryTailOracle

fun main() {
    println("p1-init=" + TryTailOracle.p1Init())
    println("p1-ret=" + TryTailOracle.p1Ret())
    println("p1-handler=" + TryTailOracle.p1Handler())
    println("p2-init=" + TryTailOracle.p2Init())
    println("p2-ret=" + TryTailOracle.p2Ret())
    println("p2-handler=" + TryTailOracle.p2Handler())
    println("p3-init=" + TryTailOracle.p3Init())
    println("p3-ret=" + TryTailOracle.p3Ret())
    println("p3-handler=" + TryTailOracle.p3Handler())
    println("p4-init=" + TryTailOracle.p4Init())
    println("p4-ret=" + TryTailOracle.p4Ret())
    println("p4-handler=" + TryTailOracle.p4Handler())
}
