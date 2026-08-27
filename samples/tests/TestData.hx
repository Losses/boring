package tests;

import boring.BinaryWriter;
import boring.GlyphMetrics;
import haxe.io.Bytes;

/**
 * Literal test data helpers for in-source test modules.
 */
class TestData {
	public static function sampleBounds():BoundsEm {
		return {
			xMin: 0.0,
			yMin: 0.0,
			xMax: 0.5,
			yMax: 0.5
		};
	}

	public static function glyphSamples():Array<GlyphMetrics> {
		return [
			{
				codePoint: 65,
				advanceEm: 0.5,
				bounds: {
					xMin: 0.0,
					yMin: 0.0,
					xMax: 0.5,
					yMax: 0.5
				}
			}
		];
	}

	public static function sampleBytes():Bytes {
		final writer = new BinaryWriter();
		writer.writeU32(0x42524731);
		return writer.finish();
	}
}
