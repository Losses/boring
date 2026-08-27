package kotlincompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;

/**
	Type mapping from the translatable Haxe subset to Kotlin, per
	docs/specs/features/14-type-system-mapping.md and stdlib rulings.
**/
class KotlinType {
	final imports: KotlinImports;

	public function new(imports: KotlinImports) {
		this.imports = imports;
	}

	public function of(t: Null<Type>): String {
		if(t == null) {
			return "Unit";
		}
		return switch(t) {
			case TAbstract(a, params):
				final abs = a.get();
				switch(pathOf(abs.pack, abs.name)) {
					case "Int": "Int";
					case "Float": "Double";
					case "Bool": "Boolean";
					case "Void": "Unit";
					case "boring.ReadOnlyArray":
						"List<" + of(params[0]) + ">";
					case "haxe.Int64":
						"Long";
					case _: of(abs.type);
				}
			case TInst(c, params):
				final cls = c.get();
				switch(pathOf(cls.pack, cls.name)) {
					case "String": "String";
					case "Array":
						"MutableList<" + of(params[0]) + ">";
					case "haxe.io.Bytes": "ByteArray";
					case "haxe.io.BytesBuffer": "BytesBuffer";
					case _:
						if(isBoringPack(cls.pack)) {
							cls.name;
						} else {
							fail(t);
						}
				}
			case TType(def, params):
				final d = def.get();
				if(isBoringPack(d.pack)) {
					d.name;
				} else if(d.pack.join(".") == "haxe.io" && d.name == "Bytes") {
					"ByteArray";
				} else if(params.length == 0) {
					of(d.type);
				} else {
					fail(t);
				}
			case TEnum(e, _):
				final en = e.get();
				if(isBoringPack(en.pack)) {
					if(en.name == "VectorError") "VectorException" else en.name;
				} else {
					fail(t);
				}
			case TFun(args, ret):
				"(" + [for(arg in args) of(arg.t)].join(", ") + ") -> " + of(ret);
			case TAnonymous(_):
				Context.error("anonymous structure types must be named typedefs before translation", Context.currentPos());
				null;
			case TDynamic(_) | TMono(_):
				fail(t);
			case TLazy(f): of(f());
		}
	}

	public function moduleBase(module: String): String {
		final parts = module.split(".");
		return parts[parts.length - 1];
	}

	function pathOf(pack: Array<String>, name: String): String {
		return pack.length == 0 ? name : pack.join(".") + "." + name;
	}

	function isBoringPack(pack: Array<String>): Bool {
		return pack.length == 1 && pack[0] == "boring";
	}

	function fail(t: Type): String {
		Context.error("type has no Kotlin lowering in the translatable subset: " + Std.string(t), Context.currentPos());
		return null;
	}
}
#end
