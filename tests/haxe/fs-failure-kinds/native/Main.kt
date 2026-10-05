// Kotlin native harness for the fs-failure-kinds fixture. The runner copies
// this file into the generated tree root and compiles it with the generated
// modules.
import fsfail.FsFailOracle
import java.io.File
import java.nio.file.Files
import java.nio.file.attribute.PosixFilePermissions

fun main() {
    val dir = File("out/fs-failure-kinds")
    dir.mkdirs()
    val missing = File(dir, "absent.txt")
    val file = File(dir, "plain.txt")
    val denied = File(dir, "denied.txt")
    file.writeText("content")
    denied.writeText("secret")

    println("missing-read=" + FsFailOracle.readIdentity(missing.path))
    println("not-a-directory-read=" + FsFailOracle.readIdentity(file.path + "/child"))
    println("write-over-directory=" + FsFailOracle.writeIdentity(dir.path))
    println("predicates-missing=" + FsFailOracle.predicatePair(missing.path))
    println("manual-catch=" + FsFailOracle.manualCatchIdentity())
    Files.setPosixFilePermissions(denied.toPath(), PosixFilePermissions.fromString("---------"))
    println("denied-read=" + FsFailOracle.readIdentity(denied.path))
    Files.setPosixFilePermissions(denied.toPath(), PosixFilePermissions.fromString("rw-r--r--"))
}
