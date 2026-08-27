package tscompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;

/**
	Type mapping from the translatable Haxe subset to TypeScript, per
	docs/specs/features/14-type-system-mapping.md and the stdlib rulings:
	haxe.io.Bytes is Uint8Array (stdlib/01), haxe.io.BytesBuffer is the
	runtime growth class (stdlib/02), haxe.Int64 stays out of value
	domain (stdlib/05), ReadOnlyArray<T> is `readonly T[]` (features/18).
**/
class TsType {
	final imports: TsImports;

	public function new(imports: TsImports) {
		this.imports = imports;
	}

	public function of(t: Null<Type>): String {
		if(t == null) {
			return "void";
		}
		return switch(t) {
			case TAbstract(a, params):
				final abs = a.get();
				switch(pathOf(abs.pack, abs.name)) {
					case "Int", "Float": "number";
					case "Bool": "boolean";
					case "Void": "void";
					case "boring.ReadOnlyArray": "readonly " + of(params[0]) + "[]";
					case "haxe.Int64":
						imports.runtime("Int64Halves");
						"Int64Halves";
					case _: of(abs.type);
				}
			case TInst(c, params):
				final cls = c.get();
				switch(pathOf(cls.pack, cls.name)) {
					case "String": "string";
					case "Array": of(params[0]) + "[]";
					case "haxe.io.Bytes": "Uint8Array";
					case "haxe.io.BytesBuffer":
						imports.runtime("BytesBuffer");
						"BytesBuffer";
					case _:
						if(isBoringPack(cls.pack)) {
							imports.type(moduleBase(cls.module), cls.name);
							cls.name;
						} else {
							fail(t);
						}
				}
			case TType(def, params):
				final d = def.get();
				if(isBoringPack(d.pack)) {
					imports.type(moduleBase(d.module), d.name);
					d.name;
				} else if(d.pack.join(".") == "haxe.io" && d.name == "Bytes") {
					"Uint8Array";
				} else if(params.length == 0) {
					of(d.type);
				} else {
					fail(t);
				}
			case TEnum(e, _):
				final en = e.get();
				if(isBoringPack(en.pack)) {
					imports.type(moduleBase(en.module), en.name);
					en.name;
				} else {
					fail(t);
				}
			case TFun(args, ret):
				"(" + [for(arg in args) '${arg.name}: ${of(arg.t)}'].join(", ") + ") => " + of(ret);
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
		Context.error("type has no TypeScript lowering in the translatable subset: " + Std.string(t), Context.currentPos());
		return null;
	}
}
#end
