package kotlincompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;

/**
	Type mapping from the translatable Haxe subset to Kotlin, per
	docs/specs/features/14-type-system-mapping.md and stdlib rulings.
	Cross-package types record their imports; the payload enum of the
	sealed error fold resolves to its exception class.
**/
class KotlinType {
	final imports: KotlinImports;
	final state: KotlinEmissionState;

	public function new(imports: KotlinImports, state: KotlinEmissionState) {
		this.imports = imports;
		this.state = state;
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
					case "std.ReadOnlyArray":
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
					"ByteArray";
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
					owner;
				} else {
					imports.requireType(en.module, en.name);
					en.name;
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

	function pathOf(pack: Array<String>, name: String): String {
		return pack.length == 0 ? name : pack.join(".") + "." + name;
	}

	function fail(t: Type): String {
		Context.error("type has no Kotlin lowering in the translatable subset: " + Std.string(t), Context.currentPos());
		return null;
	}
}
#end
