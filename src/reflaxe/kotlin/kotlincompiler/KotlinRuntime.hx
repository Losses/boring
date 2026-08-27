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

    fun run(id: String, name: String, body: () -> Unit) {
        currentTestId = id
        try {
            body()
            currentTestId = null
            recordResult(id, name, \"pass\", null)
        } catch (e: Throwable) {
            currentTestId = null
            val msg = e.message ?: e.toString()
            recordResult(id, name, \"fail\", msg)
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

    fun equals(expected: String?, actual: String?, message: String? = null) {
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
    fun formatValue(v: String?): String = if (v == null) \"null\" else \"\\\"\" + escapeJson(v) + \"\\\"\"
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

    private fun recordResult(id: String, name: String, verdict: String, message: String?) {
        val envPath = System.getenv(\"BORING_TEST_RESULTS\")
        val filePath = if (envPath != null && envPath.isNotEmpty()) envPath else \"out/test-results/kotlin.jsonl\"
        val jsonLine = if (verdict == \"pass\") {
            \"{\\\"id\\\":\\\"\" + escapeJson(id) + \"\\\",\\\"name\\\":\\\"\" + escapeJson(name) + \"\\\",\\\"verdict\\\":\\\"pass\\\"}\\n\"
        } else {
            \"{\\\"id\\\":\\\"\" + escapeJson(id) + \"\\\",\\\"name\\\":\\\"\" + escapeJson(name) + \"\\\",\\\"verdict\\\":\\\"fail\\\",\\\"message\\\":\\\"\" + escapeJson(message ?: \"\") + \"\\\"}\\n\"
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

	public static final SORTED_MAP_SOURCE = "class SortedMap<V>(private val keys: IntArray, private val values: Array<Any?>) {
    companion object {
        fun <V> builder(): SortedMapBuilder<V> = SortedMapBuilder()
    }

    fun get(key: Int): V? {
        val idx = keys.binarySearch(key)
        @Suppress(\"UNCHECKED_CAST\")
        return if (idx >= 0) values[idx] as V else null
    }

    fun has(key: Int): Boolean = keys.binarySearch(key) >= 0

    fun size(): Int = keys.size

    fun keyAt(index: Int): Int = keys[index]

    @Suppress(\"UNCHECKED_CAST\")
    fun valueAt(index: Int): V = values[index] as V
}

class SortedMapBuilder<V> {
    private val entries = ArrayList<Pair<Int, V>>()

    fun put(key: Int, value: V) {
        entries.add(Pair(key, value))
    }

    fun build(): SortedMap<V> {
        if (entries.isEmpty()) {
            return SortedMap(IntArray(0), emptyArray())
        }
        val sorted = entries.mapIndexed { idx, pair -> Triple(pair.first, idx, pair.second) }
            .sortedWith(compareBy({ it.first }, { it.second }))

        val distinctKeys = ArrayList<Int>()
        val distinctValues = ArrayList<Any?>()

        var i = 0
        while (i < sorted.size) {
            var j = i
            while (j + 1 < sorted.size && sorted[j + 1].first == sorted[i].first) {
                j++
            }
            distinctKeys.add(sorted[j].first)
            distinctValues.add(sorted[j].third)
            i = j + 1
        }

        val keyArray = IntArray(distinctKeys.size) { distinctKeys[it] }
        val valArray = distinctValues.toArray()
        return SortedMap(keyArray, valArray)
    }
}
";

	public static final SORTED_SET_SOURCE = "class SortedSet(private val keys: IntArray) {
    companion object {
        fun builder(): SortedSetBuilder = SortedSetBuilder()
    }

    fun has(key: Int): Boolean = keys.binarySearch(key) >= 0

    fun size(): Int = keys.size

    fun at(index: Int): Int = keys[index]
}

class SortedSetBuilder {
    private val keys = ArrayList<Int>()

    fun put(key: Int) {
        keys.add(key)
    }

    fun build(): SortedSet {
        if (keys.isEmpty()) {
            return SortedSet(IntArray(0))
        }
        val sorted = keys.sorted()
        val distinct = ArrayList<Int>()
        for (k in sorted) {
            if (distinct.isEmpty() || distinct[distinct.size - 1] != k) {
                distinct.add(k)
            }
        }
        return SortedSet(IntArray(distinct.size) { distinct[it] })
    }
}
";
}
#end
