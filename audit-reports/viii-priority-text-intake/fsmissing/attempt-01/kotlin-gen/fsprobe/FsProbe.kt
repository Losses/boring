package fsprobe

import boring.runtime.Console
import java.nio.file.Files
import java.nio.file.Paths

object FsProbe {
    fun missingRoot(): String {
        return "out/fs-missing/probe/definitely-missing"
    }

    fun say(label: String, text: String) {
        Console.log(label + "|" + text)
    }

    fun messageOf(error: FsProbeFault): String {
        return (if ((false)) "<not-caught>" else run {
    val bound = error
    bound.message
})
    }

    fun run() {
        val missing = FsProbe.missingRoot() + "/no-such-file.txt"
        FsProbe.say("m0", "probe-start")
        val dir = Files.isDirectory(Paths.get(missing))
        FsProbe.say("m1", "isDirectory-returned|" + dir)
        var caught = false
        var name = "<not-caught>"
        var message = "<not-caught>"
        try {
            val text = Files.readString(Paths.get(missing))
            FsProbe.say("m2", "readText-returned|" + text)
        } catch (error: FsProbeFault) {
            caught = true
            name = "haxe.Exception"
            message = FsProbe.messageOf(error)
        }
        FsProbe.say("m3", "readText-catch-ran|" + caught)
        FsProbe.say("m4", "caught-declared-class|" + name)
        FsProbe.say("m5", "caught-message|" + message)
        FsProbe.say("m6", "uncaught-region-start")
        val escaped = Files.readString(Paths.get(missing))
        FsProbe.say("m7", "uncaught-region-returned|" + escaped)
    }
}

class FsProbeFault(override val message: String) : RuntimeException(message)
