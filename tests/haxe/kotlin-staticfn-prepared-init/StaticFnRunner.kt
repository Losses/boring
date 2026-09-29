import boring.StaticFnOps

fun main() {
    val transformed = StaticFnOps.apply("a")
    check(transformed == "a!") { "apply returned " + transformed }
    check(StaticFnOps.increment() == 1) { "increment returned " + StaticFnOps.count }
    check(StaticFnOps.increment() == 2) { "increment returned " + StaticFnOps.count }
    println("KOTLIN STATICFN PREPARED INIT PASS")
}
