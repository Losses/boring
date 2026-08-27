package rustcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;

/**
	Type mapping from the translatable Haxe subset to Rust.
**/
class RustType {
	final imports: RustImports;
	final state: RustEmissionState;

	public function new(imports: RustImports, state: RustEmissionState) {
		this.imports = imports;
		this.state = state;
	}

	public function of(t: Null<Type>, isParam: Bool = false): String {
		if(t == null) {
			return "()";
		}
		return switch(t) {
			case TAbstract(a, params):
				final abs = a.get();
				switch(pathOf(abs.pack, abs.name)) {
					case "Int": "u32";
					case "Float": "f64";
					case "Bool": "bool";
					case "Void": "()";
					case "std.ReadOnlyArray":
						isParam ? "&[" + of(params[0]) + "]" : "Vec<" + of(params[0]) + ">";
					case "haxe.Int64":
						"i64";
					case _: of(abs.type, isParam);
				}
			case TInst(c, params):
				final cls = c.get();
				switch(pathOf(cls.pack, cls.name)) {
					case "String": isParam ? "&str" : "String";
					case "Array":
						isParam ? "&mut [" + of(params[0]) + "]" : "Vec<" + of(params[0]) + ">";
					case "haxe.io.Bytes":
						isParam ? "&[u8]" : "Vec<u8>";
					case "haxe.io.BytesBuffer":
						imports.requireType(cls.module, "BytesBuffer");
						"BytesBuffer";
					case _:
						imports.requireType(cls.module, cls.name);
						cls.name;
				}
			case TType(def, params):
				final d = def.get();
				if(d.pack.join(".") == "haxe.io" && d.name == "Bytes") {
					isParam ? "&[u8]" : "Vec<u8>";
				} else if(params.length == 0) {
					imports.requireType(d.module, d.name);
					d.name;
				} else {
					fail(t);
				}
			case TEnum(e, _):
				final en = e.get();
				final owner = state.payloadEnumOwners.get(en.module);
				if(owner != null) {
					imports.requireType(en.module, owner);
					owner;
				} else {
					imports.requireType(en.module, en.name);
					en.name;
				}
			case TFun(args, ret):
				"(" + [for(arg in args) of(arg.t, true)].join(", ") + ") -> " + of(ret, false);
			case TAnonymous(_):
				Context.error("anonymous structure types must be named typedefs before translation", Context.currentPos());
				null;
			case TDynamic(_) | TMono(_):
				fail(t);
			case TLazy(f): of(f(), isParam);
		}
	}

	function pathOf(pack: Array<String>, name: String): String {
		return pack.length == 0 ? name : pack.join(".") + "." + name;
	}

	function fail(t: Type): String {
		Context.error("type has no Rust lowering in the translatable subset: " + Std.string(t), Context.currentPos());
		return null;
	}
}
#end
