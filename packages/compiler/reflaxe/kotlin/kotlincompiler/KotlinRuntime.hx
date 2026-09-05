package kotlincompiler;

#if (macro || reflaxe_runtime)
/**
    Bodies of the standard-library shims, emitted on demand into the
    runtime package configured through RuntimeConfig. Each source is a
    type declaration without a package line: the emitter prefixes the
    // the configured package directive, so the source contains no namespace.
    - haxe.io.BytesBuffer: growable byte buffer sink
    - haxe.io.FPHelper: IEEE-754 64-bit float bit conversions, plus the
      binary32 value edges of feature spec 23
    - std.Console: logging
    - std.Process: process exit
    - test extern: test assertions and runner
**/
class KotlinRuntime {
    public static final BYTES_BUFFER_SOURCE = "import java.util.ArrayList

class BytesBuffer {
    private val buffer = ArrayList<Byte>()

    fun addByte(byte: Int) {
        buffer.add((byte and 0xFF).toByte())
    }

    fun add(bytes: ByteArray) {
        for (byte in bytes) {
            buffer.add(byte)
        }
    }

    fun getBytes(): ByteArray {
        val bytes = ByteArray(buffer.size)
        for (i in 0 until buffer.size) {
            bytes[i] = buffer[i]
        }
        return bytes
    }
}
";

    public static final FP_HELPER_SOURCE = "class Int64Halves(val high: Int, val low: Int)

object FPHelper {
    fun doubleToI64(value: Double): Int64Halves {
        val bits = value.toRawBits()
        val high = (bits ushr 32).toInt()
        val low = bits.toInt()
        return Int64Halves(high, low)
    }

    fun i64ToDouble(low: Int, high: Int): Double {
        val h = high.toLong() and 0xFFFFFFFFL
        val l = low.toLong() and 0xFFFFFFFFL
        val bits = (h shl 32) or l
        return Double.fromBits(bits)
    }

    // Binary32 variants of the two value edges: the same 8 wire bytes
    // decode to the f64 value, then round once to the module real; the
    // reverse widens losslessly before the bit conversion. Only the
    // float-precision=f32 lane references them (feature spec 23).
    fun i64ToF32(low: Int, high: Int): Float {
        return i64ToDouble(low, high).toFloat()
    }

    fun f32ToI64(value: Float): Int64Halves {
        return doubleToI64(value.toDouble())
    }
}
";

    public static final CONSOLE_SOURCE = "object Console {
    fun log(message: String) {
        println(message)
    }
}
";

    public static final PROCESS_SOURCE = "import kotlin.system.exitProcess

object Process {
    private var programArgs: MutableList<String> = mutableListOf()

    fun storeArgs(args: Array<String>) {
        programArgs = args.toMutableList()
    }

    fun args(): MutableList<String> = programArgs

    fun exit(code: Int) {
        exitProcess(code)
    }
}
";

    /**
        The process-local environment overlay of std.Env
        (docs/specs/stdlib/17-platform-modules.md). The JVM exposes the
        process environment read-only, so set and remove cannot reach the
        host; every std.Env call routes through this overlay, which
        records the writes and falls back to the host for the keys it has
        never seen. Get and set therefore operate on one environment view.
    **/
    public static final ENV_SOURCE = "object Env {
    private val setValues = HashMap<String, String>()
    private val removedKeys = HashSet<String>()

    fun get(key: String): String? {
        if (removedKeys.contains(key)) {
            return null
        }
        val value = setValues[key]
        if (value != null) {
            return value
        }
        return System.getenv(key)
    }

    fun set(key: String, value: String) {
        removedKeys.remove(key)
        setValues[key] = value
    }

    fun remove(key: String) {
        setValues.remove(key)
        removedKeys.add(key)
    }
}
";

    public static function testSource():String {
        // The floating-point members follow the module real of the
        // compilation (feature spec 23): TestCore is Haxe source compiled
        // through the same pipeline, so its formatFloat signature switches
        // with the compilation's real type and the delegate overloads must switch with it.
        final real = FloatPrecision.isF32() ? "Float" : "Double";
        return 'import java.io.File
import java.io.FileWriter

object Test {
    private var currentTestId: String? = null

    // Host edges of the test runtime (P6): the runner state, the raise of
    // this language, and the result-file edge. The assertion checks and
    // canonical formatting live in TestCore, compiled beside this object;
    // every member below is a thin delegate keeping the nullable surface
    // the generated tests call.
    fun currentTestIdState(): String = currentTestId ?: ""

    fun run(id: String, name: String, body: () -> Unit) {
        currentTestId = id
        try {
            body()
            currentTestId = null
            recordResult(id, name, "pass", null)
        } catch (e: Throwable) {
            currentTestId = null
            val msg = e.message ?: e.toString()
            recordResult(id, name, "fail", msg)
            throw e
        }
    }

    fun ok(condition: Boolean, message: String? = null) {
        TestCore.ok(condition, message ?: "")
    }

    fun fail(message: String) {
        TestCore.fail(message)
    }

    fun equals(expected: Boolean?, actual: Boolean?, message: String? = null) {
        if (expected == null || actual == null) {
            if (expected != actual) {
                TestCore.reportFailure(message ?: "", formatValue(expected), formatValue(actual))
            }
        } else {
            TestCore.equalsBool(expected, actual, message ?: "")
        }
    }

    fun equals(expected: Int?, actual: Int?, message: String? = null) {
        if (expected == null || actual == null) {
            if (expected != actual) {
                TestCore.reportFailure(message ?: "", formatValue(expected), formatValue(actual))
            }
        } else {
            TestCore.equalsInt(expected, actual, message ?: "")
        }
    }

    fun equals(expected: ${real}?, actual: ${real}?, message: String? = null) {
        if (expected == null || actual == null) {
            if (expected != actual) {
                TestCore.reportFailure(message ?: "", formatValue(expected), formatValue(actual))
            }
        } else {
            TestCore.equalsFloat(expected, actual, message ?: "")
        }
    }

    fun equals(expected: String?, actual: String?, message: String? = null) {
        if (expected == null || actual == null) {
            if (expected != actual) {
                TestCore.reportFailure(message ?: "", formatValue(expected), formatValue(actual))
            }
        } else {
            TestCore.equalsString(expected, actual, message ?: "")
        }
    }

    fun reportFailure(message: String?, expectedStr: String, actualStr: String) {
        TestCore.reportFailure(message ?: "", expectedStr, actualStr)
    }

    fun formatValue(v: Boolean?): String = if (v == null) "null" else TestCore.formatBool(v)
    fun formatValue(v: Int?): String = if (v == null) "null" else TestCore.formatInt(v)
    fun formatValue(v: ${real}?): String = if (v == null) "null" else TestCore.formatFloat(v)
    fun formatValue(v: String?): String = if (v == null) "null" else "\\"\" + TestCore.escapeJson(v) + "\\"\"
    fun formatValue(v: ByteArray): String = TestCore.formatBytes(v)

    fun formatFloat(v: ${real}): String = TestCore.formatFloat(v)

    fun formatBytes(b: ByteArray): String = TestCore.formatBytes(b)

    fun escapeJson(s: String): String = TestCore.escapeJson(s)

    private fun recordResult(id: String, name: String, verdict: String, message: String?) {
        val jsonLine = TestCore.resultLine(id, name, verdict == "fail", message ?: "")
        val envPath = System.getenv("BORING_TEST_RESULTS")
        val filePath = if (envPath != null && envPath.isNotEmpty()) envPath else "out/test-results/kotlin.jsonl"
        val file = File(filePath)
        val parent = file.parentFile
        if (parent != null && !parent.exists()) {
            parent.mkdirs()
        }
        FileWriter(file, true).use { writer ->
            writer.write(jsonLine)
        }
    }
}
';
    }
}
#end
