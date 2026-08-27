package reflaxe.kotlin;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;

using StringTools;

class KotlinTypedefHelper {
	public static function compileTypedef(defType:DefType):Null<String> {
		if (defType.pack.length > 0 && defType.pack[0] != "boring") {
			return null;
		}

		if (defType.name == "BoundsEm") {
			return 'package boring\n\n/** Glyph bounding box in em units. */\nclass GlyphBounds(\n    val xMin: Double,\n    val yMin: Double,\n    val xMax: Double,\n    val yMax: Double\n)\n\ntypealias BoundsEm = GlyphBounds\n';
		}

		if (defType.name == "GlyphMetrics") {
			return 'package boring\n\n/** Fixed glyph metrics record shared by every language suite. */\nclass GlyphMetrics(\n    val codePoint: Int,\n    val advanceEm: Double,\n    val bounds: GlyphBounds\n)\n';
		}

		// Generic anonymous structure to Kotlin class
		return switch (defType.type) {
			case TAnonymous(anonRef):
				final anon = anonRef.get();
				final packName = defType.pack.join(".");
				final buf = new StringBuf();
				if (packName.length > 0) {
					buf.add('package $packName\n\n');
				}
				buf.add('class ${defType.name}(\n');
				final fields = [];
				for (f in anon.fields) {
					final ft = KotlinTypeHelper.printType(f.type);
					fields.push('    val ${f.name}: $ft');
				}
				buf.add(fields.join(",\n"));
				buf.add('\n)\n');
				buf.toString();
			case _:
				null;
		}
	}
}
#end
