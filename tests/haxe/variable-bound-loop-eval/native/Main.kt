import vble.Probe

/**
 * Native invocation driver for the variable-bound-loop-eval fixture (Kotlin).
 * The runner copies this file into the generated tree root and compiles it
 * with the generated sources, so it sits in the default package while the
 * probe object sits in `vble`. The driver only observes: it calls the three
 * generated probe functions once each and prints the three returned
 * bound-read counts. The generated main() calls the fixture shadow of
 * haxe.Log (a no-op), so this driver is the only printer of the observation
 * line. It takes no verdict; the runner compares the printed observation with
 * the authored expectation.
 */
fun main() {
    val local = Probe.localBound()
    val length = Probe.growingLength()
    val control = Probe.doubleControl()
    println("local=$local length=$length control=$control")
}
