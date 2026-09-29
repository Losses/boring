import composition.KeyCompositionObserve
import kotlin.system.exitProcess

/**
 * Native invocation harness for the Kotlin generated tree of the signed key
 * composition fixture. kotlinc builds this file against the generated library
 * jar and java runs it; the harness prints the text one generated observation
 * function returns. It holds no ordering decision and re-implements no
 * comparator. The case name is the first program argument.
 */
fun main(args: Array<String>) {
    val name = if (args.isEmpty()) "<none>" else args[0]
    val observation: String = when (name) {
        "direct-int" -> KeyCompositionObserve.directInt()
        "direct-int-extremes" -> KeyCompositionObserve.directIntExtremes()
        "typedef-int" -> KeyCompositionObserve.typedefInt()
        "typedef-int-extremes" -> KeyCompositionObserve.typedefIntExtremes()
        "composite-nullable" -> KeyCompositionObserve.compositeNullable()
        "composite-extremes" -> KeyCompositionObserve.compositeExtremes()
        else -> {
            System.err.println("signed-key-composition harness: unknown case $name")
            exitProcess(2)
        }
    }
    println(observation)
}
