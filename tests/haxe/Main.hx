package;

import boring.BinaryReader;
import boring.BinaryWriter;
import boring.Console;
import boring.GlyphMetrics;
import boring.Process;
import boring.VectorCodec;
import haxe.io.Bytes;

/**
 * Typed test entry for the Haxe side. compile.hxml builds this file to
 * JavaScript and the test script executes it with bun. The runner uses no
 * Dynamic and no reflection: record equality is field-wise, byte agreement is
 * compared against the committed vector hex, and failures set a nonzero exit
 * code.
 */
class Main {
	static var failures:Int = 0;
	static var passes:Int = 0;

	static final VECTOR_RECORDS:Array<GlyphMetrics> = [
		{
			codePoint: 65,
			advanceEm: 0.5,
			bounds: { xMin: 0.03125, yMin: -0.21875, xMax: 0.46875, yMax: 0.03125 }
		},
		{
			codePoint: 19969,
			advanceEm: 1.0,
			bounds: { xMin: 0.03125, yMin: -0.875, xMax: 0.96875, yMax: 0.03125 }
		},
		{
			codePoint: 65292,
			advanceEm: 0.5,
			bounds: { xMin: 0.03125, yMin: -0.21875, xMax: 0.46875, yMax: 0.03125 }
		},
		{
			codePoint: 65311,
			advanceEm: 0.75,
			bounds: { xMin: 0.0625, yMin: -0.15625, xMax: 0.6875, yMax: 0.0625 }
		}
	];

	static final EXPECTED_HEX:String = "4252473100000004"
		+ "000000413fe00000000000003fa0000000000000bfcc0000000000003fde0000000000003fa0000000000000"
		+ "00004e013ff00000000000003fa0000000000000bfec0000000000003fef0000000000003fa0000000000000"
		+ "0000ff0c3fe00000000000003fa0000000000000bfcc0000000000003fde0000000000003fa0000000000000"
		+ "0000ff1f3fe80000000000003fb0000000000000bfc40000000000003fe60000000000003fb0000000000000";

	static function recordEquals(left:GlyphMetrics, right:GlyphMetrics):Bool {
		return left.codePoint == right.codePoint
			&& left.advanceEm == right.advanceEm
			&& left.bounds.xMin == right.bounds.xMin
			&& left.bounds.yMin == right.bounds.yMin
			&& left.bounds.xMax == right.bounds.xMax
			&& left.bounds.yMax == right.bounds.yMax;
	}

	static function recordsEqual(left:Array<GlyphMetrics>, right:Array<GlyphMetrics>):Bool {
		if (left.length != right.length) return false;
		for (index in 0...left.length) {
			if (!recordEquals(left[index], right[index])) return false;
		}
		return true;
	}

	static function expectTrue(label:String, condition:Bool):Void {
		if (condition) {
			passes++;
			Console.log('pass $label');
		} else {
			failures++;
			Console.log('FAIL $label');
		}
	}

	static function main():Void {
		final encoded = VectorCodec.encode(VECTOR_RECORDS);
		expectTrue("encoded length matches the committed vector", encoded.length == 184);
		expectTrue("encoded hex matches the committed vector", encoded.toHex() == EXPECTED_HEX);

		final decoded = VectorCodec.decode(Bytes.ofHex(EXPECTED_HEX));
		expectTrue("decoded records match the source records", recordsEqual(decoded, VECTOR_RECORDS));

		final roundTripped = VectorCodec.decode(VectorCodec.encode(VECTOR_RECORDS));
		expectTrue("round trip preserves every record", recordsEqual(roundTripped, VECTOR_RECORDS));

		final writer = new BinaryWriter();
		writer.writeU16(0x1234);
		writer.writeU32(0x56789abc);
		final reader = new BinaryReader(writer.finish());
		expectTrue("u16 round trip", reader.readU16() == 0x1234);
		expectTrue("u32 round trip", reader.readU32() == 0x56789abc);
		expectTrue("reader fully consumed", reader.remaining() == 0);

		var badMagicThrew = false;
		try {
			VectorCodec.decode(Bytes.ofHex("5858585800000000"));
		} catch (error:haxe.Exception) {
			badMagicThrew = true;
		}
		expectTrue("bad magic raises an exception", badMagicThrew);

		if (failures > 0) {
			Console.log('$failures failure(s)');
			Process.exit(1);
		}
		Console.log('all ${passes} haxe checks passed');
	}
}
