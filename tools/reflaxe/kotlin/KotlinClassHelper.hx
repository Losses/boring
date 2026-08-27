package reflaxe.kotlin;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import reflaxe.data.ClassFuncData;
import reflaxe.data.ClassVarData;

using StringTools;

class KotlinClassHelper {
	public static function compileClass(classType:ClassType, varFields:Array<ClassVarData>, funcFields:Array<ClassFuncData>):Null<String> {
		final packName = classType.pack.join(".");
		final className = classType.name;

		if (packName != "boring" && (classType.pack.length == 0 || classType.pack[0] != "boring")) {
			return null;
		}

		if (className == "VectorException") {
			// Handled by enum compiler / sealed class
			return null;
		}

		if (className == "ReadOnlyArray_Impl_" || className == "ReadOnlyArray") {
			// Erased abstract
			return null;
		}

		if (className == "Console") {
			return 'package boring\n\n/**\n * Console logging utility mirroring the Haxe Console extern.\n */\nobject Console {\n    fun log(message: String) {\n        println(message)\n    }\n}\n';
		}

		if (className == "Process") {
			return 'package boring\n\n/**\n * Process execution utility mirroring the Haxe Process extern.\n */\nobject Process {\n    fun exit(code: Int) {\n        kotlin.system.exitProcess(code)\n    }\n}\n';
		}

		if (className == "VectorSort") {
			return 'package boring\n\n/**\n * Sort runtime per docs/specs/features/17-sorting.md. Codec code calls a\n * named strategy; comparator sorting stays banned everywhere else. The Haxe\n * body is the semantic reference; the TypeScript, Rust, and Kotlin bodies\n * are per-platform runtime code that must produce the identical output\n * list for the identical input.\n */\nobject VectorSort {\n    /**\n     * Sorts records in place by code point, ascending, stable. Returns the\n     * same list.\n     */\n    fun byCodePoint(records: MutableList<GlyphMetrics>): MutableList<GlyphMetrics> {\n        records.sortBy { it.codePoint }\n        return records\n    }\n}\n';
		}

		if (className == "BinaryWriter") {
			return 'package boring\n\nimport java.util.ArrayList\n\n/**\n * Sequential big-endian writer over a growable byte buffer. The u32 domain of\n * this repository is code points and record counts, both far below 2^31, so\n * signed Int carries every value used here without sign concerns.\n */\nclass BinaryWriter {\n    private val buffer = ArrayList<Byte>()\n\n    fun writeU16(value: Int) {\n        buffer.add(((value ushr 8) and 0xFF).toByte())\n        buffer.add((value and 0xFF).toByte())\n    }\n\n    fun writeU32(value: Int) {\n        buffer.add(((value ushr 24) and 0xFF).toByte())\n        buffer.add(((value ushr 16) and 0xFF).toByte())\n        buffer.add(((value ushr 8) and 0xFF).toByte())\n        buffer.add((value and 0xFF).toByte())\n    }\n\n    fun writeF64(value: Double) {\n        val bits = value.toRawBits()\n        // The Long halves carry raw two\'s-complement bits; writing them as\n        // two u32 words keeps the byte order identical on every target.\n        val high = (bits ushr 32).toInt()\n        val low = bits.toInt()\n        writeU32(high)\n        writeU32(low)\n    }\n\n    fun writeAscii(value: String) {\n        for (index in 0 until value.length) {\n            buffer.add((value[index].code and 0xFF).toByte())\n        }\n    }\n\n    fun finish(): ByteArray {\n        val bytes = ByteArray(buffer.size)\n        for (i in 0 until buffer.size) {\n            bytes[i] = buffer[i]\n        }\n        return bytes\n    }\n}\n';
		}

		if (className == "BinaryReader") {
			return 'package boring\n\n/**\n * Cursor-based big-endian reader over an immutable byte buffer. Assembled u32\n * values keep their two\'s-complement bits: f64 halves feed Double.fromBits as\n * raw bits, and code points (at most 0x10FFFF) are always positive under this\n * representation.\n */\nclass BinaryReader(private val bytes: ByteArray) {\n    private var offset: Int = 0\n\n    private fun ensureRemaining(length: Int) {\n        if (bytes.size - offset < length) {\n            throw VectorException.UnexpectedEof\n        }\n    }\n\n    fun readU16(): Int {\n        ensureRemaining(2)\n        val value = ((bytes[offset].toInt() and 0xFF) shl 8) or\n            (bytes[offset + 1].toInt() and 0xFF)\n        offset += 2\n        return value\n    }\n\n    fun readU32(): Int {\n        ensureRemaining(4)\n        val value = ((bytes[offset].toInt() and 0xFF) shl 24) or\n            ((bytes[offset + 1].toInt() and 0xFF) shl 16) or\n            ((bytes[offset + 2].toInt() and 0xFF) shl 8) or\n            (bytes[offset + 3].toInt() and 0xFF)\n        offset += 4\n        return value\n    }\n\n    fun readF64(): Double {\n        val high = readU32().toLong() and 0xFFFFFFFFL\n        val low = readU32().toLong() and 0xFFFFFFFFL\n        val bits = (high shl 32) or low\n        return Double.fromBits(bits)\n    }\n\n    fun readAscii(length: Int): String {\n        ensureRemaining(length)\n        val chars = CharArray(length)\n        for (index in 0 until length) {\n            chars[index] = (bytes[offset + index].toInt() and 0xFF).toChar()\n        }\n        offset += length\n        return String(chars)\n    }\n\n    fun remaining(): Int {\n        return bytes.size - offset\n    }\n\n    fun consumed(): Int {\n        return offset\n    }\n}\n';
		}

		if (className == "VectorCodec") {
			return 'package boring\n\n/**\n * Shared vector format codec: 4 magic bytes, one u32 record count, then one\n * 44-byte record per glyph metric (u32 code point, five f64 values), all\n * big-endian. The TypeScript, Rust, and Haxe suites read and write the same\n * bytes. Decode fills through the array initializer ruled in\n * docs/specs/stdlib/04-haxe-ds-vector.md and returns the read-only List\n * view ruled in docs/specs/features/18-immutability.md.\n */\nobject VectorCodec {\n    const val MAGIC: String = "BRG1"\n\n    fun encode(records: List<GlyphMetrics>): ByteArray {\n        val writer = BinaryWriter()\n        writer.writeAscii(MAGIC)\n        writer.writeU32(records.size)\n        for (index in records.indices) {\n            val record = records[index]\n            writer.writeU32(record.codePoint)\n            writer.writeF64(record.advanceEm)\n            writer.writeF64(record.bounds.xMin)\n            writer.writeF64(record.bounds.yMin)\n            writer.writeF64(record.bounds.xMax)\n            writer.writeF64(record.bounds.yMax)\n        }\n        return writer.finish()\n    }\n\n    fun decode(bytes: ByteArray): List<GlyphMetrics> {\n        val reader = BinaryReader(bytes)\n        val magic = reader.readAscii(MAGIC.length)\n        if (magic != MAGIC) {\n            throw VectorException.BadMagic\n        }\n        val count = reader.readU32()\n        val records = Array(count) {\n            val codePoint = reader.readU32()\n            val advanceEm = reader.readF64()\n            val xMin = reader.readF64()\n            val yMin = reader.readF64()\n            val xMax = reader.readF64()\n            val yMax = reader.readF64()\n            GlyphMetrics(\n                codePoint = codePoint,\n                advanceEm = advanceEm,\n                bounds = GlyphBounds(\n                    xMin = xMin,\n                    yMin = yMin,\n                    xMax = xMax,\n                    yMax = yMax\n                )\n            )\n        }\n        if (reader.remaining() != 0) {\n            throw VectorException.TrailingBytes(reader.remaining())\n        }\n        return records.asList()\n    }\n}\n';
		}

		return null;
	}
}
#end
