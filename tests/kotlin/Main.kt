import boring.BoundsEm
import boring.BinaryReader
import boring.BinaryWriter
import boring.GlyphMetrics
import boring.VectorCodec
import boring.VectorException
import boring.VectorSort
import java.util.ArrayList
import kotlin.system.exitProcess

/**
 * Typed test entry for the Kotlin side. kotlinc builds this file to a jar
 * and the test script executes it with java. The runner uses no reflection:
 * record equality is field-wise, byte agreement is compared against the
 * committed vector hex, and failures set a nonzero exit code.
 */
object Main {
    private var failures: Int = 0
    private var passes: Int = 0

    private val VECTOR_RECORDS: List<GlyphMetrics> = listOf(
        GlyphMetrics(
            codePoint = 65,
            advanceEm = 0.5,
            bounds = BoundsEm(xMin = 0.03125, yMin = -0.21875, xMax = 0.46875, yMax = 0.03125)
        ),
        GlyphMetrics(
            codePoint = 19969,
            advanceEm = 1.0,
            bounds = BoundsEm(xMin = 0.03125, yMin = -0.875, xMax = 0.96875, yMax = 0.03125)
        ),
        GlyphMetrics(
            codePoint = 65292,
            advanceEm = 0.5,
            bounds = BoundsEm(xMin = 0.03125, yMin = -0.21875, xMax = 0.46875, yMax = 0.03125)
        ),
        GlyphMetrics(
            codePoint = 65311,
            advanceEm = 0.75,
            bounds = BoundsEm(xMin = 0.0625, yMin = -0.15625, xMax = 0.6875, yMax = 0.0625)
        )
    )

    private const val EXPECTED_HEX: String = "4252473100000004" +
        "000000413fe00000000000003fa0000000000000bfcc0000000000003fde0000000000003fa0000000000000" +
        "00004e013ff00000000000003fa0000000000000bfec0000000000003fef0000000000003fa0000000000000" +
        "0000ff0c3fe00000000000003fa0000000000000bfcc0000000000003fde0000000000003fa0000000000000" +
        "0000ff1f3fe80000000000003fb0000000000000bfc40000000000003fe60000000000003fb0000000000000"

    private fun recordEquals(left: GlyphMetrics, right: GlyphMetrics): Boolean {
        return left.codePoint == right.codePoint &&
            left.advanceEm == right.advanceEm &&
            left.bounds.xMin == right.bounds.xMin &&
            left.bounds.yMin == right.bounds.yMin &&
            left.bounds.xMax == right.bounds.xMax &&
            left.bounds.yMax == right.bounds.yMax
    }

    private fun recordsEqual(left: List<GlyphMetrics>, right: List<GlyphMetrics>): Boolean {
        if (left.size != right.size) return false
        for (index in left.indices) {
            if (!recordEquals(left[index], right[index])) return false
        }
        return true
    }

    private fun expectTrue(label: String, condition: Boolean) {
        if (condition) {
            passes++
            println("pass $label")
        } else {
            failures++
            println("FAIL $label")
        }
    }

    private fun hexToBytes(hex: String): ByteArray {
        val count = hex.length / 2
        val data = ByteArray(count)
        for (i in 0 until count) {
            val high = Character.digit(hex[i * 2], 16)
            val low = Character.digit(hex[i * 2 + 1], 16)
            data[i] = ((high shl 4) or low).toByte()
        }
        return data
    }

    private fun bytesToHex(bytes: ByteArray): String {
        val hexChars = "0123456789abcdef"
        val chars = CharArray(bytes.size * 2)
        for (i in bytes.indices) {
            val v = bytes[i].toInt() and 0xFF
            chars[i * 2] = hexChars[v ushr 4]
            chars[i * 2 + 1] = hexChars[v and 0x0F]
        }
        return String(chars)
    }

    @JvmStatic
    fun main(args: Array<String>) {
        val encoded = VectorCodec.encode(VECTOR_RECORDS)
        expectTrue("encoded length matches the committed vector", encoded.size == 184)
        expectTrue("encoded hex matches the committed vector", bytesToHex(encoded) == EXPECTED_HEX)

        val decoded = VectorCodec.decode(hexToBytes(EXPECTED_HEX))
        expectTrue("decoded records match the source records", recordsEqual(decoded, VECTOR_RECORDS))

        val roundTripped = VectorCodec.decode(VectorCodec.encode(VECTOR_RECORDS))
        expectTrue("round trip preserves every record", recordsEqual(roundTripped, VECTOR_RECORDS))

        val writer = BinaryWriter()
        writer.writeU16(0x1234)
        writer.writeU32(0x56789abc)
        val reader = BinaryReader(writer.finish())
        expectTrue("u16 round trip", reader.readU16() == 0x1234)
        expectTrue("u32 round trip", reader.readU32() == 0x56789abc)
        expectTrue("reader fully consumed", reader.remaining() == 0)

        var badMagicVariant: VectorException? = null
        try {
            VectorCodec.decode(hexToBytes("5858585800000000"))
        } catch (error: VectorException) {
            badMagicVariant = error
        }
        expectTrue("bad magic throws the BadMagic variant", badMagicVariant == VectorException.BadMagic)

        var truncatedVariant: VectorException? = null
        try {
            VectorCodec.decode(hexToBytes("4252473100000001"))
        } catch (error: VectorException) {
            truncatedVariant = error
        }
        expectTrue("truncated vector throws the UnexpectedEof variant", truncatedVariant == VectorException.UnexpectedEof)

        var trailingBytesVariant: VectorException? = null
        try {
            val padded = hexToBytes(EXPECTED_HEX) + byteArrayOf(0)
            VectorCodec.decode(padded)
        } catch (error: VectorException) {
            trailingBytesVariant = error
        }
        expectTrue("trailing bytes throws the TrailingBytes variant", trailingBytesVariant == VectorException.TrailingBytes(1))

        runSortChecks()

        if (failures > 0) {
            println("$failures failure(s)")
            exitProcess(1)
        }
        println("all $passes kotlin checks passed")
    }

    // Sort fixture and oracle shared verbatim with tests/ts/vector-sort.test.ts,
    // tests/haxe/Main.hx, and tests/rust/vector.rs; the trees must produce
    // identical outputs.
    private val SORT_SHUFFLED_KEYS: List<Int> = listOf(
        0x82A1, 0x78E2, 0x76EF, 0x6371, 0x4E00, 0x0020, 0x7AD5, 0x74FC, 0x694A, 0x6F23,
        0x6D30, 0x8A6D, 0x617E, 0x7EBB, 0x3105, 0x5BA5, 0x6B3D, 0x8687, 0x7116, 0x7CC8,
        0xFF01, 0x8494, 0x80AE, 0x59B2, 0x4FF3, 0x4E00, 0x9FFF, 0x57BF, 0xFF01, 0x6564,
        0x53D9, 0x5D98, 0x6757, 0x3105, 0x5F8B, 0x7309, 0x55CC, 0x51E6, 0x4E00, 0x887A
    )

    private val SORT_SORTED_KEYS: List<Int> = listOf(
        0x20, 0x3105, 0x3105, 0x4E00, 0x4E00, 0x4E00, 0x4FF3, 0x51E6, 0x53D9, 0x55CC,
        0x57BF, 0x59B2, 0x5BA5, 0x5D98, 0x5F8B, 0x617E, 0x6371, 0x6564, 0x6757, 0x694A,
        0x6B3D, 0x6D30, 0x6F23, 0x7116, 0x7309, 0x74FC, 0x76EF, 0x78E2, 0x7AD5, 0x7CC8,
        0x7EBB, 0x80AE, 0x82A1, 0x8494, 0x8687, 0x887A, 0x8A6D, 0x9FFF, 0xFF01, 0xFF01
    )

    private fun sortRecordsFromKeys(keys: List<Int>): ArrayList<GlyphMetrics> {
        val records = ArrayList<GlyphMetrics>(keys.size)
        for (index in keys.indices) {
            // advanceEm marks the input position for the stability assertion.
            records.add(
                GlyphMetrics(
                    codePoint = keys[index],
                    advanceEm = index.toDouble(),
                    bounds = BoundsEm(xMin = 0.0, yMin = 0.0, xMax = 0.0, yMax = 0.0)
                )
            )
        }
        return records
    }

    private fun runSortChecks() {
        val records = sortRecordsFromKeys(SORT_SHUFFLED_KEYS)
        val result = VectorSort.byCodePoint(records)
        expectTrue("sort returns the same array", result === records)
        var keysMatch = true
        for (index in SORT_SORTED_KEYS.indices) {
            if (result[index].codePoint != SORT_SORTED_KEYS[index]) {
                keysMatch = false
            }
        }
        expectTrue("sort matches the shared oracle", keysMatch)
        var stable = true
        for (index in 1 until result.size) {
            if (result[index].codePoint == result[index - 1].codePoint &&
                result[index].advanceEm < result[index - 1].advanceEm
            ) {
                stable = false
            }
        }
        expectTrue("equal keys keep input order", stable)
    }
}

fun main(args: Array<String>) {
    Main.main(args)
}
