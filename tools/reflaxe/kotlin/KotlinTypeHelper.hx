package reflaxe.kotlin;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;

using StringTools;

class KotlinTypeHelper {
	public static function printType(type:Type, inListContext:Bool = false):String {
		return switch (type) {
			case TAbstract(absRef, params):
				final abs = absRef.get();
				switch (abs.name) {
					case "Int", "Int32": "Int";
					case "Int64": "Long";
					case "Float": "Double";
					case "Single": "Float";
					case "Bool": "Boolean";
					case "Void": "Unit";
					case "Null":
						if (params.length > 0) printType(params[0]) + "?" else "Any?";
					case "ReadOnlyArray":
						if (params.length > 0) "List<" + printType(params[0]) + ">" else "List<Any>";
					case _:
						if (abs.pack.length > 0 && abs.pack[0] == "boring") {
							abs.name;
						} else {
							abs.name;
						}
				}
			case TInst(clsRef, params):
				final cls = clsRef.get();
				final fullName = (cls.pack.length > 0 ? cls.pack.join(".") + "." : "") + cls.name;
				switch (fullName) {
					case "String": "String";
					case "Array":
						if (params.length > 0) {
							final inner = printType(params[0]);
							if (inListContext) "MutableList<" + inner + ">" else "Array<" + inner + ">";
						} else {
							if (inListContext) "MutableList<Any>" else "Array<Any>";
						}
					case "haxe.io.Bytes": "ByteArray";
					case "haxe.io.BytesBuffer": "ArrayList<Byte>";
					case "boring.VectorException": "VectorException";
					case _:
						if (cls.name == "BoundsEm") "GlyphBounds"
						else cls.name;
				}
			case TEnum(enumRef, _):
				final enm = enumRef.get();
				if (enm.name == "VectorError") "VectorException" else enm.name;
			case TType(defRef, params):
				final def = defRef.get();
				switch (def.name) {
					case "BoundsEm": "GlyphBounds";
					case "GlyphMetrics": "GlyphMetrics";
					case "ReadOnlyArray":
						if (params.length > 0) "List<" + printType(params[0]) + ">" else "List<Any>";
					case _: def.name;
				}
			case TAnonymous(anonRef):
				"Any";
			case TDynamic(_):
				"Any";
			case TMono(monoRef):
				final t = monoRef.get();
				if (t != null) printType(t, inListContext) else "Any";
			case TLazy(lazyFunc):
				printType(lazyFunc(), inListContext);
			case _:
				"Any";
		}
	}
}
#end
