package kotlincompiler;

#if (macro || reflaxe_runtime)

/**
	Source of runtime utilities emitted alongside generated Kotlin files:
	- BytesBuffer: growable byte buffer sink
	- FPHelper: IEEE-754 64-bit float bit conversions
	- Console: logging utility mirroring Haxe Console extern
	- Process: exit utility mirroring Haxe Process extern
**/
class KotlinRuntime {
	public static final BYTES_BUFFER_SOURCE = "package boring

import java.util.ArrayList

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

	public static final FP_HELPER_SOURCE = "package boring

class Int64Halves(val high: Int, val low: Int)

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

	public static final CONSOLE_SOURCE = "package boring

object Console {
    fun log(message: String) {
        println(message)
    }
}
";

	public static final PROCESS_SOURCE = "package boring

import kotlin.system.exitProcess

object Process {
    fun exit(code: Int) {
        exitProcess(code)
    }
}
";
}
#end
