import ksfshapes.StaticFnObjectShape
import ksfshapes.StaticFnShapes

fun main() {
    val shaped = StaticFnShapes.applyShaped("a")
    check(shaped == "a<>") { "companion shaped returned " + shaped }
    val absent = StaticFnShapes.applyNullable("")
    if (absent != null) {
        error("companion nullable absent case returned [" + absent + "] class " + absent::class.qualifiedName)
    }
    val present = StaticFnShapes.applyNullable("a")
    check(present == "a!") { "companion nullable returned " + present }
    val objectShaped = StaticFnObjectShape.apply("ab")
    check(objectShaped == "[abab]") { "object shaped returned " + objectShaped }
    println("KOTLIN STATICFN SHAPES PASS")
}