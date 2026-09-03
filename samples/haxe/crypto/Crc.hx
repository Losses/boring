package haxe.crypto;

import haxe.io.Bytes;

/** Portable parameterized CRC calculator. */
class Crc {
	public static function hash(model:CrcModel, data:Bytes, previous:Int = 0):Int {
		var crc = previous == 0 ? model.init : unfinalize(model, previous);
		final mask = bitMask(model.width);
		if (model.refin) {
			final poly = reflect(model.poly, model.width);
			for (i in 0...data.length) {
				crc = crc ^ data.get(i);
				for (_ in 0...8) crc = (crc & 1) != 0 ? (crc >>> 1) ^ poly : crc >>> 1;
			}
		} else {
			final top = model.width == 32 ? -2147483648 : 1 << (model.width - 1);
			for (i in 0...data.length) {
				crc = crc ^ (data.get(i) << (model.width - 8));
				for (_ in 0...8) crc = (crc & top) != 0 ? (crc << 1) ^ model.poly : crc << 1;
				crc &= mask;
			}
		}
		return finalize(model, crc) & mask;
	}

	public static function crc1(data:Bytes, previous:Int = 0):Int { var sum = previous; for (i in 0...data.length) sum = (sum + data.get(i)) & 255; return sum; }
	public static function crc8(data:Bytes, previous:Int = 0):Int return hash(new CrcModel(8, 0x07, 0, false, false, 0), data, previous);
	public static function crc81wire(data:Bytes, previous:Int = 0):Int return hash(new CrcModel(8, 0x31, 0, true, true, 0), data, previous);
	public static function crc8dvbs2(data:Bytes, previous:Int = 0):Int return hash(new CrcModel(8, 0xD5, 0, false, false, 0), data, previous);
	public static function crc16(data:Bytes, previous:Int = 0):Int return hash(new CrcModel(16, 0x8005, 0, true, true, 0), data, previous);
	public static function crc16ccitt(data:Bytes, previous:Int = 0):Int return hash(new CrcModel(16, 0x1021, 0xFFFF, false, false, 0), data, previous);
	public static function crc16modbus(data:Bytes, previous:Int = 0):Int return hash(new CrcModel(16, 0x8005, 0xFFFF, true, true, 0), data, previous);
	public static function crc16kermit(data:Bytes, previous:Int = 0):Int return hash(new CrcModel(16, 0x1021, 0, true, true, 0), data, previous);
	public static function crc16xmodem(data:Bytes, previous:Int = 0):Int return hash(new CrcModel(16, 0x1021, 0, false, false, 0), data, previous);
	public static function crc24(data:Bytes, previous:Int = 0):Int return hash(new CrcModel(24, 0x864CFB, 0xB704CE, false, false, 0), data, previous);
	public static function crc32(data:Bytes, previous:Int = 0):Int return hash(new CrcModel(32, 0x04C11DB7, -1, true, true, -1), data, previous);
	public static function crc32mpeg2(data:Bytes, previous:Int = 0):Int return hash(new CrcModel(32, 0x04C11DB7, -1, false, false, 0), data, previous);
	public static function crcjam(data:Bytes, previous:Int = 0):Int return hash(new CrcModel(32, 0x04C11DB7, -1, true, true, 0), data, previous);

	static function finalize(model:CrcModel, crc:Int):Int return (model.refout != model.refin ? reflect(crc, model.width) : crc) ^ model.xorout;
	static function unfinalize(model:CrcModel, value:Int):Int { var crc = value ^ model.xorout; return model.refout != model.refin ? reflect(crc, model.width) : crc; }
	static function bitMask(width:Int):Int return width == 32 ? -1 : (1 << width) - 1;
	static function reflect(value:Int, width:Int):Int { var result = 0; for (i in 0...width) { result = (result << 1) | ((value >>> i) & 1); } return result; }
}
