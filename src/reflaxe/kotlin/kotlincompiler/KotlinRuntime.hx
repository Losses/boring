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

    fun equals(expected: Boolean?, actual: Boolean?, message: String? = null) {
        if (expected != actual) {
            val canonical = formatCanonicalMessage(currentTestId ?: \"\", message, formatValue(expected), formatValue(actual), true)
            throw AssertionError(canonical)
        }
    }

    fun equals(expected: Int?, actual: Int?, message: String? = null) {
        if (expected != actual) {
            val canonical = formatCanonicalMessage(currentTestId ?: \"\", message, formatValue(expected), formatValue(actual), true)
            throw AssertionError(canonical)
        }
    }

    fun equals(expected: Double?, actual: Double?, message: String? = null) {
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

    fun formatValue(v: Boolean?): String = if (v == null) \"null\" else if (v) \"true\" else \"false\"
    fun formatValue(v: Int?): String = if (v == null) \"null\" else v.toString()
    fun formatValue(v: Double?): String = if (v == null) \"null\" else formatFloat(v)
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

    fun get(key: Int): V? {
        for (i in entries.indices.reversed()) {
            if (entries[i].first == key) {
                return entries[i].second
            }
        }
        return null
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

class SortedMapStr<V>(private val keys: Array<String>, private val values: Array<Any?>) {
    companion object {
        fun <V> builder(): SortedMapStrBuilder<V> = SortedMapStrBuilder()
    }

    fun get(key: String): V? {
        val idx = keys.binarySearch(key)
        @Suppress(\"UNCHECKED_CAST\")
        return if (idx >= 0) values[idx] as V else null
    }

    fun has(key: String): Boolean = keys.binarySearch(key) >= 0

    fun size(): Int = keys.size

    fun keyAt(index: Int): String = keys[index]

    @Suppress(\"UNCHECKED_CAST\")
    fun valueAt(index: Int): V = values[index] as V
}

class SortedMapStrBuilder<V> {
    private val entries = ArrayList<Pair<String, V>>()

    fun put(key: String, value: V) {
        entries.add(Pair(key, value))
    }

    fun get(key: String): V? {
        for (i in entries.indices.reversed()) {
            if (entries[i].first == key) {
                return entries[i].second
            }
        }
        return null
    }

    fun build(): SortedMapStr<V> {
        if (entries.isEmpty()) {
            return SortedMapStr(emptyArray(), emptyArray())
        }
        val sorted = entries.mapIndexed { idx, pair -> Triple(pair.first, idx, pair.second) }
            .sortedWith(compareBy({ it.first }, { it.second }))

        val distinctKeys = ArrayList<String>()
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

        val keyArray = Array(distinctKeys.size) { distinctKeys[it] }
        val valArray = distinctValues.toArray()
        return SortedMapStr(keyArray, valArray)
    }
}

class SortedMapObj<K, V>(private val keys: Array<Any?>, private val values: Array<Any?>, private val comparator: (K, K) -> Int) {
    companion object {
        fun <K, V> builder(comparator: (K, K) -> Int): SortedMapObjBuilder<K, V> = SortedMapObjBuilder(comparator)
    }

    fun get(key: K): V? {
        var low = 0
        var high = keys.size - 1
        while (low <= high) {
            val mid = (low + high) ushr 1
            @Suppress(\"UNCHECKED_CAST\")
            val midVal = keys[mid] as K
            val cmp = comparator(midVal, key)
            if (cmp < 0) {
                low = mid + 1
            } else if (cmp > 0) {
                high = mid - 1
            } else {
                @Suppress(\"UNCHECKED_CAST\")
                return values[mid] as V
            }
        }
        return null
    }

    fun has(key: K): Boolean {
        var low = 0
        var high = keys.size - 1
        while (low <= high) {
            val mid = (low + high) ushr 1
            @Suppress(\"UNCHECKED_CAST\")
            val midVal = keys[mid] as K
            val cmp = comparator(midVal, key)
            if (cmp < 0) {
                low = mid + 1
            } else if (cmp > 0) {
                high = mid - 1
            } else {
                return true
            }
        }
        return false
    }

    fun size(): Int = keys.size

    @Suppress(\"UNCHECKED_CAST\")
    fun keyAt(index: Int): K = keys[index] as K

    @Suppress(\"UNCHECKED_CAST\")
    fun valueAt(index: Int): V = values[index] as V
}

class SortedMapObjBuilder<K, V>(private val comparator: (K, K) -> Int) {
    private val entries = ArrayList<Pair<K, V>>()

    fun put(key: K, value: V) {
        entries.add(Pair(key, value))
    }

    fun get(key: K): V? {
        for (i in entries.indices.reversed()) {
            if (comparator(entries[i].first, key) == 0) {
                return entries[i].second
            }
        }
        return null
    }

    fun build(): SortedMapObj<K, V> {
        if (entries.isEmpty()) {
            return SortedMapObj(emptyArray(), emptyArray(), comparator)
        }
        val sorted = entries.mapIndexed { idx, pair -> Triple(pair.first, idx, pair.second) }
            .sortedWith(Comparator { a, b ->
                val cmp = comparator(a.first, b.first)
                if (cmp != 0) cmp else a.second.compareTo(b.second)
            })

        val distinctKeys = ArrayList<Any?>()
        val distinctValues = ArrayList<Any?>()

        var i = 0
        while (i < sorted.size) {
            var j = i
            while (j + 1 < sorted.size && comparator(sorted[j + 1].first, sorted[i].first) == 0) {
                j++
            }
            distinctKeys.add(sorted[j].first)
            distinctValues.add(sorted[j].third)
            i = j + 1
        }

        return SortedMapObj(distinctKeys.toArray(), distinctValues.toArray(), comparator)
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

class SortedSetStr(private val keys: Array<String>) {
    companion object {
        fun builder(): SortedSetStrBuilder = SortedSetStrBuilder()
    }

    fun has(key: String): Boolean = keys.binarySearch(key) >= 0

    fun size(): Int = keys.size

    fun at(index: Int): String = keys[index]
}

class SortedSetStrBuilder {
    private val keys = ArrayList<String>()

    fun put(key: String) {
        keys.add(key)
    }

    fun build(): SortedSetStr {
        if (keys.isEmpty()) {
            return SortedSetStr(emptyArray())
        }
        val sorted = keys.sorted()
        val distinct = ArrayList<String>()
        for (k in sorted) {
            if (distinct.isEmpty() || distinct[distinct.size - 1] != k) {
                distinct.add(k)
            }
        }
        return SortedSetStr(Array(distinct.size) { distinct[it] })
    }
}

class SortedSetObj<K>(private val keys: Array<Any?>, private val comparator: (K, K) -> Int) {
    companion object {
        fun <K> builder(comparator: (K, K) -> Int): SortedSetObjBuilder<K> = SortedSetObjBuilder(comparator)
    }

    fun has(key: K): Boolean {
        var low = 0
        var high = keys.size - 1
        while (low <= high) {
            val mid = (low + high) ushr 1
            @Suppress(\"UNCHECKED_CAST\")
            val midVal = keys[mid] as K
            val cmp = comparator(midVal, key)
            if (cmp < 0) {
                low = mid + 1
            } else if (cmp > 0) {
                high = mid - 1
            } else {
                return true
            }
        }
        return false
    }

    fun size(): Int = keys.size

    @Suppress(\"UNCHECKED_CAST\")
    fun at(index: Int): K = keys[index] as K
}

class SortedSetObjBuilder<K>(private val comparator: (K, K) -> Int) {
    private val keys = ArrayList<K>()

    fun put(key: K) {
        keys.add(key)
    }

    fun build(): SortedSetObj<K> {
        if (keys.isEmpty()) {
            return SortedSetObj(emptyArray(), comparator)
        }
        val sorted = keys.sortedWith(Comparator { a, b -> comparator(a, b) })
        val distinct = ArrayList<Any?>()
        for (k in sorted) {
            @Suppress(\"UNCHECKED_CAST\")
            if (distinct.isEmpty() || comparator(distinct[distinct.size - 1] as K, k) != 0) {
                distinct.add(k)
            }
        }
        return SortedSetObj(distinct.toArray(), comparator)
    }
}
";

	/**
		Runtime module behind std.UStringRT (docs/specs/stdlib/10-unicode-string-access.md).
		Code-point-addressed walks over UTF-16 storage; the domain checks live
		in the inline wrappers of std.UString and never reach these functions.
	**/
	public static final USTRING_SOURCE = "
object UString {
    fun count(s: String): Int {
        var total = 0
        var i = 0
        while (i < s.length) {
            i += charWidth(s, i)
            total += 1
        }
        return total
    }

    fun at(s: String, index: Int): Int? {
        if (index < 0) {
            return null
        }
        var remaining = index
        var i = 0
        while (i < s.length) {
            if (remaining == 0) {
                return codePointAt(s, i)
            }
            remaining -= 1
            i += charWidth(s, i)
        }
        return null
    }

    fun slice(s: String, from: Int, to: Int): String {
        val total = count(s)
        val start = if (from < 0) 0 else if (from > total) total else from
        val end = if (to > total) total else if (to < 0) 0 else to
        if (start >= end) {
            return \"\"
        }
        var unitStart = 0
        var unitEnd = 0
        var pos = 0
        var i = 0
        while (pos < end) {
            if (pos == start) {
                unitStart = i
            }
            i += charWidth(s, i)
            pos += 1
        }
        unitEnd = i
        return s.substring(unitStart, unitEnd)
    }

    fun toCodePoints(s: String): MutableList<Int> {
        val out: MutableList<Int> = ArrayList()
        var i = 0
        while (i < s.length) {
            out.add(codePointAt(s, i))
            i += charWidth(s, i)
        }
        return out
    }

    fun fromCodePoint(code: Int): String {
        if (code < 0x10000) {
            return code.toChar().toString()
        }
        val offset = code - 0x10000
        val high = (0xD800 + (offset shr 10)).toChar()
        val low = (0xDC00 + (offset and 0x3FF)).toChar()
        return String(charArrayOf(high, low))
    }

    fun fromCodePoints(codes: MutableList<Int>): String {
        val builder = StringBuilder()
        for (i in 0 until codes.size) {
            val code = codes[i]
            if (code < 0x10000) {
                builder.append(code.toChar())
            } else {
                val offset = code - 0x10000
                builder.append((0xD800 + (offset shr 10)).toChar())
                builder.append((0xDC00 + (offset and 0x3FF)).toChar())
            }
        }
        return builder.toString()
    }

    private fun charWidth(s: String, i: Int): Int {
        val c = s[i].code
        if (c in 0xD800..0xDBFF && i + 1 < s.length) {
            val next = s[i + 1].code
            if (next in 0xDC00..0xDFFF) {
                return 2
            }
        }
        return 1
    }

    private fun codePointAt(s: String, i: Int): Int {
        val c = s[i].code
        if (c in 0xD800..0xDBFF && i + 1 < s.length) {
            val next = s[i + 1].code
            if (next in 0xDC00..0xDFFF) {
                return 0x10000 + ((c - 0xD800) shl 10) + (next - 0xDC00)
            }
        }
        return c
    }
}
";
}
#end
