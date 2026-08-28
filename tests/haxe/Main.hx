package;

import boring.BinaryReader;
import boring.BinaryWriter;
import std.Console;
import boring.GlyphMetrics;
import std.Process;
import std.ReadOnlyArray;
import std.UString;
import std.UStringException;
import std.UStringFault;
import boring.VectorCodec;
import boring.VectorError;
import boring.VectorException;
import boring.VectorSort;
import runtime.Graphemes;
import runtime.UString as RuntimeUString;
import UStringPlatform;
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

	static function recordsEqual(left:ReadOnlyArray<GlyphMetrics>, right:ReadOnlyArray<GlyphMetrics>):Bool {
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
		// The externs of std.UStringRT and std.Graphemes resolve to the
		// compiled resident modules runtime.UString and runtime.Graphemes,
		// the same classes stage one binds for TestMain. runtime.UString
		// walks strings through std.UStringPlatform, bound to the UTF-16
		// cursor implementation beside this harness.
		js.Syntax.code("globalThis.std = globalThis.std || {}; globalThis.std.UStringRT = {0};", RuntimeUString);
		js.Syntax.code("globalThis.std.UStringPlatform = {0};", UStringPlatform);
		js.Syntax.code("globalThis.std.Graphemes = {0};", Graphemes);

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

		var badMagicVariant:Null<VectorError> = null;
		try {
			VectorCodec.decode(Bytes.ofHex("5858585800000000"));
		} catch (error:VectorException) {
			badMagicVariant = error.error;
		}
		expectTrue("bad magic throws the BadMagic variant", badMagicVariant == BadMagic);

		var truncatedVariant:Null<VectorError> = null;
		try {
			VectorCodec.decode(Bytes.ofHex("4252473100000001"));
		} catch (error:VectorException) {
			truncatedVariant = error.error;
		}
		expectTrue("truncated vector throws the UnexpectedEof variant", truncatedVariant == UnexpectedEof);

		// The decodable count domain is [0, 2^31) per docs/specs/binary/01-wire-format.md.
		var hugeCountVariant:Null<VectorError> = null;
		try {
			VectorCodec.decode(Bytes.ofHex("42524731ffffffff"));
		} catch (error:VectorException) {
			hugeCountVariant = error.error;
		}
		expectTrue("huge count throws the CountOverflow variant", hugeCountVariant == CountOverflow);

		var boundaryCountVariant:Null<VectorError> = null;
		try {
			VectorCodec.decode(Bytes.ofHex("4252473180000000"));
		} catch (error:VectorException) {
			boundaryCountVariant = error.error;
		}
		expectTrue("boundary count throws the CountOverflow variant", boundaryCountVariant == CountOverflow);

		// std.UString construction domain and stage-one value answers per
		// docs/specs/stdlib/10-unicode-string-access.md. The fault paths run
		// here because typed catch has no transpiler lowering yet; the
		// four-side harness covers the value paths in tests.UStringTests.
		expectTrue("bmp cjk counts by code point", UString.count("提椠排版") == 4);
		expectTrue("supplementary cjk reads whole", UString.at("𠀀一𠀁", 2) == 0x20001);

		var surrogateFault:Null<UStringFault> = null;
		try {
			UString.fromCodePoint(0xD800);
		} catch (error:UStringException) {
			surrogateFault = error.fault;
		}
		expectTrue("surrogate code point throws the InvalidCodePoint variant", faultEquals(surrogateFault, InvalidCodePoint(0xD800)));

		var negativeFault:Null<UStringFault> = null;
		try {
			UString.fromCodePoints([0x4E2D, -1]);
		} catch (error:UStringException) {
			negativeFault = error.fault;
		}
		expectTrue("negative code point throws the InvalidCodePoint variant", faultEquals(negativeFault, InvalidCodePoint(-1)));

		runSortChecks();

		if (failures > 0) {
			Console.log('$failures failure(s)');
			Process.exit(1);
		}
		Console.log('all ${passes} haxe checks passed');
	}

	// Sort fixture and oracle shared verbatim with tests/ts/vector-sort.test.ts
	// and tests/rust/vector.rs; the trees must produce identical outputs.
	static final SORT_SHUFFLED_KEYS:Array<Int> = [
		0x82A1, 0x78E2, 0x76EF, 0x6371, 0x4E00, 0x0020, 0x7AD5, 0x74FC, 0x694A, 0x6F23,
		0x6D30, 0x8A6D, 0x617E, 0x7EBB, 0x3105, 0x5BA5, 0x6B3D, 0x8687, 0x7116, 0x7CC8,
		0xFF01, 0x8494, 0x80AE, 0x59B2, 0x4FF3, 0x4E00, 0x9FFF, 0x57BF, 0xFF01, 0x6564,
		0x53D9, 0x5D98, 0x6757, 0x3105, 0x5F8B, 0x7309, 0x55CC, 0x51E6, 0x4E00, 0x887A
	];

	static final SORT_SORTED_KEYS:Array<Int> = [
		0x20, 0x3105, 0x3105, 0x4E00, 0x4E00, 0x4E00, 0x4FF3, 0x51E6, 0x53D9, 0x55CC,
		0x57BF, 0x59B2, 0x5BA5, 0x5D98, 0x5F8B, 0x617E, 0x6371, 0x6564, 0x6757, 0x694A,
		0x6B3D, 0x6D30, 0x6F23, 0x7116, 0x7309, 0x74FC, 0x76EF, 0x78E2, 0x7AD5, 0x7CC8,
		0x7EBB, 0x80AE, 0x82A1, 0x8494, 0x8687, 0x887A, 0x8A6D, 0x9FFF, 0xFF01, 0xFF01
	];

	static function sortRecordsFromKeys(keys:Array<Int>):Array<GlyphMetrics> {
		final records = new Array<GlyphMetrics>();
		for (index in 0...keys.length) {
			// advanceEm marks the input position for the stability assertion.
			records.push({
				codePoint: keys[index],
				advanceEm: index,
				bounds: { xMin: 0, yMin: 0, xMax: 0, yMax: 0 }
			});
		}
		return records;
	}

	// Enums with arguments need structural comparison; this keeps the
	// fault checks free of reflection.
	static function faultEquals(left:Null<UStringFault>, right:UStringFault):Bool {
		if (left == null) return false;
		return switch [left, right] {
			case [InvalidCodePoint(a), InvalidCodePoint(b)]: a == b;
			case _: false;
		}
	}

	static function runSortChecks():Void {
		final records = sortRecordsFromKeys(SORT_SHUFFLED_KEYS);
		final result = VectorSort.byCodePoint(records);
		expectTrue("sort returns the same array", result == records);
		var keysMatch = true;
		for (index in 0...SORT_SORTED_KEYS.length) {
			if (result[index].codePoint != SORT_SORTED_KEYS[index]) {
				keysMatch = false;
			}
		}
		expectTrue("sort matches the shared oracle", keysMatch);
		var stable = true;
		for (index in 1...result.length) {
			if (result[index].codePoint == result[index - 1].codePoint
				&& result[index].advanceEm < result[index - 1].advanceEm) {
				stable = false;
			}
		}
		expectTrue("equal keys keep input order", stable);
	}
}
