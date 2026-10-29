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
    public static final BYTES_BUFFER_SOURCE = "class BytesBuffer {
    private val buffer = mutableListOf<Byte>()

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

    public static final USTRING_SOURCE = "object UString {
    private fun codeAt(s: String, cursor: Int): Int {
        val c = s[cursor].code
        if (c >= 0xD800 && c <= 0xDBFF && cursor + 1 < s.length) {
            val n = s[cursor + 1].code
            if (n >= 0xDC00 && n <= 0xDFFF) return 0x10000 + ((c - 0xD800) shl 10) + (n - 0xDC00)
        }
        return c
    }
    private fun advance(s: String, cursor: Int): Int {
        val c = s[cursor].code
        return cursor + (if (c >= 0xD800 && c <= 0xDBFF && cursor + 1 < s.length && s[cursor + 1].code >= 0xDC00 && s[cursor + 1].code <= 0xDFFF) 2 else 1)
    }
    fun count(s: String): Int {
        var total = 0
        var cursor = 0
        while (cursor < s.length) { total += 1; cursor = advance(s, cursor) }
        return total
    }
    fun at(s: String, index: Int): Int? {
        if (index < 0) return null
        var remaining = index
        var cursor = 0
        while (cursor < s.length) {
            if (remaining == 0) return codeAt(s, cursor)
            remaining -= 1
            cursor = advance(s, cursor)
        }
        return null
    }
    fun slice(s: String, start: Int, end: Int? = null): String {
        val length = count(s)
        val from = start.coerceIn(0, length)
        val until = (end ?: length).coerceIn(0, length)
        if (until <= from) return \"\"
        var ordinal = 0
        var startCursor = 0
        var cursor = 0
        while (ordinal < until) {
            if (ordinal == from) startCursor = cursor
            cursor = advance(s, cursor)
            ordinal += 1
        }
        return s.substring(startCursor, cursor)
    }
    fun fromCodePoint(codePoint: Int): String {
        if (codePoint < 0x10000) return codePoint.toChar().toString()
        val v = codePoint - 0x10000
        return (0xD800 + (v shr 10)).toChar().toString() + (0xDC00 + (v and 0x3FF)).toChar().toString()
    }
    fun fromCodePoints(codePoints: Array<Int>): String = codePoints.joinToString(\"\") { fromCodePoint(it) }
    fun fromCodePoints(codePoints: List<Int>): String = codePoints.joinToString(\"\") { fromCodePoint(it) }
    fun toCodePoints(s: String): Array<Int> {
        val out = mutableListOf<Int>()
        var cursor = 0
        while (cursor < s.length) { out.add(codeAt(s, cursor)); cursor = advance(s, cursor) }
        return out.toTypedArray()
    }
    fun compareTo(a: String, b: String): Int = a.compareTo(b)
}
";

    public static final LIST_FILL_SOURCE = "object ListFill {
    @Suppress(\"UNCHECKED_CAST\")
    fun <T> nCopies(size: Int, value: T?): List<T> = List(size) { value as T }
}
";

    public static function fpHelperSource():String {
        // The binary32 value edges follow the module real of the
        // compilation (feature spec 23): Haxe Float is binary32 under
        // float-precision=f32 and binary64 otherwise, but floatToI32 and
        // i32ToFloat always operate on the binary32 bit pattern. The f32
        // configuration passes the Float real directly; the f64
        // configuration passes the widened Double and narrows through
        // Float for the bit conversion, matching the Haxe std
        // implementation which rounds to binary32 before reading the bits.
        final real = FloatPrecision.isF32() ? "Float" : "Double";
        final i32ToFloatBody = FloatPrecision.isF32() ? "Float.fromBits(value)" : "Float.fromBits(value).toDouble()";
        return StringTools.replace(StringTools.replace("class Int64Halves(val high: Int, val low: Int)

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
    // reverse widens losslessly before the bit conversion (feature spec 23).
    fun i64ToF32(low: Int, high: Int): Float {
        return i64ToDouble(low, high).toFloat()
    }

    fun floatToI32(value: __REAL__): Int = value.toFloat().toRawBits()
    fun i32ToFloat(value: Int): __REAL__ = __I32TOFLOAT__

    fun f32ToI64(value: Float): Int64Halves {
        return doubleToI64(value.toDouble())
    }

    fun formatFloat(value: Double): String = formatFloatText(value.toString())

    fun formatFloat(value: Float): String = formatFloatText(value.toString())

    private fun formatFloatText(raw: String): String {
        var text = raw.replace('E', 'e')
        if (text == \"0.0\" || text == \"-0.0\") return \"0\"
        var negative = text.startsWith(\"-\")
        if (negative) text = text.substring(1)
        val parts = text.split('e')
        var digits = parts[0].replace(\".\", \"\")
        var position = parts[0].indexOf('.').let { if (it < 0) parts[0].length else it }
        if (parts.size == 2) position += parts[1].toIntOrNull() ?: 0
        while (digits.length > 1 && digits.startsWith(\"0\")) { digits = digits.substring(1); position-- }
        if (position >= -5 && position <= 21) {
            var plain = when {
                position <= 0 -> \"0.\" + \"0\".repeat(-position) + digits
                position >= digits.length -> digits + \"0\".repeat(position - digits.length)
                else -> digits.substring(0, position) + \".\" + digits.substring(position)
            }
            while (plain.contains('.') && plain.endsWith('0')) plain = plain.dropLast(1)
            if (plain.endsWith('.')) plain = plain.dropLast(1)
            return (if (negative) \"-\" else \"\") + plain
        }
        while (digits.length > 1 && digits.endsWith(\"0\")) digits = digits.dropLast(1)
        val exponent = position - 1
        val mantissa = if (digits.length == 1) digits else digits.substring(0, 1) + \".\" + digits.substring(1)
        return (if (negative) \"-\" else \"\") + mantissa + \"e\" + (if (exponent >= 0) \"+\" else \"\") + exponent
    }
}

", "__REAL__", real), "__I32TOFLOAT__", i32ToFloatBody);
    }

    /**
        std.Console declares `@:native("console")`, so the typer presents
        the extern under the native spelling while this object carries the
        declaration name. Every reference and its import go through
        KotlinImports.declarationName, which recovers the declaration name
        from the module (std.Console declares Console); the two spellings
        therefore agree, and the Kotlin resolves.
    **/
    public static final CONSOLE_SOURCE = "object Console {
    fun log(message: String) {
        println(message)
    }
    fun error(message: String) {
        System.err.println(message)
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

    fun cwd(): String = System.getProperty(\"user.dir\")

    fun platform(): String {
        val name = System.getProperty(\"os.name\").lowercase()
        return if (name.contains(\"mac\")) \"darwin\" else if (name.contains(\"win\")) \"windows\" else \"linux\"
    }

    fun run(command: String, args: MutableList<String>, cwd: String, env: MutableList<std.ProcessEnv>): std.ProcessResult {
        val builder = ProcessBuilder(listOf(command) + args)
        builder.directory(java.io.File(cwd))
        for (entry in env) builder.environment()[entry.name] = entry.value
        val child = builder.start()
        var stdout = \"\"
        var stderr = \"\"
        val outThread = Thread { stdout = child.inputStream.bufferedReader().readText() }
        val errThread = Thread { stderr = child.errorStream.bufferedReader().readText() }
        outThread.start()
        errThread.start()
        val code = child.waitFor()
        outThread.join()
        errThread.join()
        return std.ProcessResult(code = code, stdout = stdout, stderr = stderr)
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
import ${RuntimeConfig.requireImportName("module haxe.io.FPHelper")}.FPHelper

object Test {
    private var currentTestId: String? = null

    // Host edges of the test runtime (P6): the runner state, the raise of
    // this language, and the result-file edge. The assertion checks and
    // canonical formatting live in TestCore, compiled beside this object;
    // every member below is a thin delegate keeping the nullable surface
    // the generated tests call.
    fun currentTestIdState(): String = currentTestId ?: ""

    // The wall-clock budget of one test, in milliseconds. The generated
    // entry has no runner timer of its own, so the entry decides: a body
    // that overruns the budget raises through the same path as a failed
    // assertion and reaches the results file as a failure.
    private fun timeoutBudgetMs(): Long {
        val raw = System.getenv("BORING_TEST_TIMEOUT_MS")
        val parsed = raw?.toLongOrNull()
        return if (parsed != null && parsed > 0) parsed else 5000L
    }

    // A test this target excludes (feature spec 19): the entry does not
    // run the body and writes the not-applicable record instead, so the
    // id stays in the cross-target set.
    fun recordNotApplicable(id: String, name: String) {
        recordResult(id, name, "not_applicable", null)
    }

    fun run(id: String, name: String, body: () -> Unit) {
        currentTestId = id
        val budgetMs = timeoutBudgetMs()
        val startedAt = System.nanoTime()
        try {
            body()
            val elapsedMs = (System.nanoTime() - startedAt) / 1000000L
            if (elapsedMs >= budgetMs) {
                throw AssertionError("this test timed out after " + budgetMs + "ms")
            }
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

    fun formatFloat(v: ${real}): String = FPHelper.formatFloat(v)

    fun formatBytes(b: ByteArray): String = TestCore.formatBytes(b)

    fun escapeJson(s: String): String = TestCore.escapeJson(s)

    private fun recordResult(id: String, name: String, verdict: String, message: String?) {
        val jsonLine = if (verdict == "not_applicable") {
            TestCore.notApplicableLine(id, name)
        } else {
            TestCore.resultLine(id, name, verdict == "fail", message ?: "")
        }
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
