import comparison.ComparisonObserve
import kotlin.system.exitProcess

/**
 * Native invocation harness for the Kotlin generated tree of the comparison
 * observation fixture. kotlinc builds this file against the generated library
 * jar and java runs it; the harness prints the text one generated observation
 * function returns. It holds no ordering decision and re-implements no
 * comparator. The case name is the first program argument.
 */
fun main(args: Array<String>) {
    val name = if (args.isEmpty()) "<none>" else args[0]
    val observation: String = when (name) {
        "int-ordinary" -> ComparisonObserve.intOrdinary()
        "int-extremes" -> ComparisonObserve.intExtremes()
        "array-order" -> ComparisonObserve.arrayOrder()
        "nullable-order" -> ComparisonObserve.nullableOrder()
        "string-order" -> ComparisonObserve.stringOrder()
        else -> {
            System.err.println("comparison harness: unknown case $name")
            exitProcess(2)
        }
    }
    println(observation)
}
