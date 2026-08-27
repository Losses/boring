package boring

import kotlin.system.exitProcess

object Process {
    fun exit(code: Int) {
        exitProcess(code)
    }
}
