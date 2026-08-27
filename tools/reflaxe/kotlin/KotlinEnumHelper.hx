package reflaxe.kotlin;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import reflaxe.data.EnumOptionData;

using StringTools;

class KotlinEnumHelper {
	public static function compileEnum(enumType:EnumType, options:Array<EnumOptionData>):String {
		final packName = enumType.pack.join(".");
		final isVectorError = (enumType.name == "VectorError" || enumType.name == "VectorException");
		final name = isVectorError ? "VectorException" : enumType.name;

		final buf = new StringBuf();
		if (packName.length > 0) {
			buf.add('package ' + packName + '\n\n');
		}

		if (isVectorError) {
			buf.add('/**\n');
			buf.add(' * Failure identity of the vector codec, shared by every language tree as\n');
			buf.add(' * ruled in docs/specs/features/06-errors-and-results.md. The variant set\n');
			buf.add(' * matches the Rust `VectorError` enum, the TypeScript `VectorError` union,\n');
			buf.add(' * and the Haxe `VectorError` enum one to one. Messages are display text\n');
			buf.add(' * derived from the variant; no consumer reads them back.\n');
			buf.add(' */\n');
			buf.add('sealed class VectorException(message: String) : RuntimeException(message) {\n');
			buf.add('    data object BadMagic : VectorException("bad vector magic")\n');
			buf.add('    data object CountOverflow : VectorException("record count exceeds u32")\n');
			buf.add('    data object UnexpectedEof : VectorException("vector ended mid-record")\n');
			buf.add('    data class TrailingBytes(val remaining: Int) :\n');
			buf.add('        VectorException("trailing bytes in vector: ' + '$' + 'remaining")\n');
			buf.add('}\n');
			return buf.toString();
		}

		// Generic enum -> sealed interface or enum class
		var hasPayload = false;
		for (opt in options) {
			if (opt.args.length > 0) {
				hasPayload = true;
				break;
			}
		}

		if (hasPayload) {
			buf.add('sealed interface ' + name + ' {\n');
			for (opt in options) {
				if (opt.args.length == 0) {
					buf.add('    data object ' + opt.name + ' : ' + name + '\n');
				} else {
					final args = opt.args.map(a -> 'val ' + a.name + ': ' + KotlinTypeHelper.printType(a.type)).join(", ");
					buf.add('    data class ' + opt.name + '(' + args + ') : ' + name + '\n');
				}
			}
			buf.add('}\n');
		} else {
			buf.add('enum class ' + name + ' {\n');
			final names = options.map(o -> '    ' + o.name).join(",\n");
			buf.add(names);
			buf.add('\n}\n');
		}

		return buf.toString();
	}
}
#end
