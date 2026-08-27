package kotlincompiler;

#if (macro || reflaxe_runtime)

/**
	Bodies of the standard-library shims, emitted on demand into the
	runtime package configured through RuntimeConfig. Each source is a
	type declaration without a package line: the emitter prefixes the
	configured package directive, so no source namespace is baked in.
	- haxe.io.BytesBuffer: growable byte buffer sink
	- haxe.io.FPHelper: IEEE-754 64-bit float bit conversions
	- std.Console: logging
	- std.Process: process exit
	- std.Test: test assertions and runner
**/
class KotlinRuntime {
	public static final BYTES_BUFFER_SOURCE = "import java.util.ArrayList

class BytesBuffer {
    private val buffer = ArrayList<Byte>()

    fun addByte(byte: Int) {
        buffer.add((byte and 0xFF).toByte())
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
    fun exit(code: Int) {
        exitProcess(code)
    }
}
";

	public static final TEST_SOURCE = "import java.io.File
import java.io.FileWriter

object Test {
    private var currentTestId: String? = null

    fun run(id: String, body: () -> Unit) {
        currentTestId = id
        try {
            body()
            currentTestId = null
            recordResult(id, \"pass\", null)
        } catch (e: Throwable) {
            currentTestId = null
            val msg = e.message ?: e.toString()
            recordResult(id, \"fail\", msg)
            throw e
        }
    }

    fun ok(condition: Boolean, message: String? = null) {
        if (!condition) {
            val canonical = formatCanonicalMessage(currentTestId ?: \"\", message, null, null, false)
            throw AssertionError(canonical)
        }
    }

    fun fail(message: String) {
        val canonical = formatCanonicalMessage(currentTestId ?: \"\", message, null, null, false)
        throw AssertionError(canonical)
    }

    fun equals(expected: Boolean, actual: Boolean, message: String? = null) {
        if (expected != actual) {
            val canonical = formatCanonicalMessage(currentTestId ?: \"\", message, formatValue(expected), formatValue(actual), true)
            throw AssertionError(canonical)
        }
    }

    fun equals(expected: Int, actual: Int, message: String? = null) {
        if (expected != actual) {
            val canonical = formatCanonicalMessage(currentTestId ?: \"\", message, formatValue(expected), formatValue(actual), true)
            throw AssertionError(canonical)
        }
    }

    fun equals(expected: Double, actual: Double, message: String? = null) {
        // IEEE equality: NaN != NaN
        if (expected != actual) {
            val canonical = formatCanonicalMessage(currentTestId ?: \"\", message, formatValue(expected), formatValue(actual), true)
            throw AssertionError(canonical)
        }
    }

    fun equals(expected: String, actual: String, message: String? = null) {
        if (expected != actual) {
            val canonical = formatCanonicalMessage(currentTestId ?: \"\", message, formatValue(expected), formatValue(actual), true)
            throw AssertionError(canonical)
        }
    }

    fun reportFailure(message: String?, expectedStr: String, actualStr: String) {
        val canonical = formatCanonicalMessage(currentTestId ?: \"\", message, expectedStr, actualStr, true)
        throw AssertionError(canonical)
    }

    fun formatValue(v: Boolean): String = if (v) \"true\" else \"false\"
    fun formatValue(v: Int): String = v.toString()
    fun formatValue(v: Double): String = formatFloat(v)
    fun formatValue(v: String): String = \"\\\"\" + escapeJson(v) + \"\\\"\"
    fun formatValue(v: ByteArray): String = formatBytes(v)

    fun formatFloat(v: Double): String {
        if (v.isNaN()) return \"NaN\"
        if (v == Double.POSITIVE_INFINITY) return \"Infinity\"
        if (v == Double.NEGATIVE_INFINITY) return \"-Infinity\"
        if (v == 0.0 || v == -0.0) return \"0\"
        var s = v.toString()
        if (s.endsWith(\".0\")) {
            s = s.substring(0, s.length - 2)
        }
        return s
    }

    fun formatBytes(b: ByteArray): String {
        val hexChars = \"0123456789abcdef\"
        val result = StringBuilder(b.size * 2)
        for (byte in b) {
            val i = byte.toInt() and 0xFF
            result.append(hexChars[i ushr 4])
            result.append(hexChars[i and 0x0F])
        }
        return result.toString()
    }

    fun escapeJson(s: String): String {
        val buf = StringBuilder()
        for (i in 0 until s.length) {
            val c = s[i]
            val code = c.code
            when (c) {
                '\"' -> buf.append(\"\\\\\\\"\")
                '\\\\' -> buf.append(\"\\\\\\\\\")
                '\\n' -> buf.append(\"\\\\n\")
                '\\r' -> buf.append(\"\\\\r\")
                '\\t' -> buf.append(\"\\\\t\")
                else -> {
                    if (code < 0x20) {
                        buf.append(\"\\\\u\" + String.format(\"%04x\", code))
                    } else {
                        buf.append(c)
                    }
                }
            }
        }
        return buf.toString()
    }

    fun formatCanonicalMessage(id: String, message: String?, expectedStr: String?, actualStr: String?, isEquals: Boolean): String {
        val lines = ArrayList<String>()
        lines.add(\"test failed: $id\")
        if (message != null && message.isNotEmpty()) {
            lines.add(\"  message: $message\")
        }
        if (isEquals) {
            lines.add(\"  expected: \" + (expectedStr ?: \"\"))
            lines.add(\"  actual:   \" + (actualStr ?: \"\"))
        }
        return lines.joinToString(\"\\n\")
    }

    private fun recordResult(id: String, verdict: String, message: String?) {
        val envPath = System.getenv(\"BORING_TEST_RESULTS\")
        val filePath = if (envPath != null && envPath.isNotEmpty()) envPath else \"out/test-results/kotlin.jsonl\"
        val jsonLine = if (verdict == \"pass\") {
            \"{\\\"id\\\":\\\"\" + escapeJson(id) + \"\\\",\\\"verdict\\\":\\\"pass\\\"}\\n\"
        } else {
            \"{\\\"id\\\":\\\"\" + escapeJson(id) + \"\\\",\\\"verdict\\\":\\\"fail\\\",\\\"message\\\":\\\"\" + escapeJson(message ?: \"\") + \"\\\"}\\n\"
        }
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
";
}
#end
