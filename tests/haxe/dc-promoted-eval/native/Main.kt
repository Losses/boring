import dcpe.DoubleEvalControl
import dcpe.EvalProbe
import kotlin.system.exitProcess

/**
 * Native invocation driver for the dc-promoted-eval fixture (Kotlin). The
 * runner copies this file into the generated tree root and compiles it with the
 * generated sources, so it sits in the default package while the probe classes
 * sit in `dcpe`. The driver only observes: it resets the probe counter, calls
 * the probe once, and prints the counter. It takes no verdict; the runner
 * compares the printed observation with the authored expectation.
 */
fun main(args: Array<String>) {
    val requested = if (args.isEmpty()) "<none>" else args[0]
    when (requested) {
        "promoted" -> {
            EvalProbe.reset()
            val acc = EvalProbe.promotedOnce()
            println("case=promoted acc=$acc callCount=${EvalProbe.callCount}")
        }
        "double" -> {
            DoubleEvalControl.reset()
            val acc = DoubleEvalControl.doubleOnce()
            println("case=double acc=$acc callCount=${DoubleEvalControl.callCount}")
        }
        else -> {
            System.err.println("dc-promoted-eval kotlin driver: unknown case $requested")
            exitProcess(2)
        }
    }
}
