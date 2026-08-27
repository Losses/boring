package kotlincompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;

enum KeyDomain {
	IntKey;
	StringKey;
	StructKey(def: DefType, fields: Array<ClassField>);
}

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
					case "Null": of(params[0]) + "?";
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
					case "std.SortedMap":
						switch(classifyKey(params[0])) {
							case IntKey:
								imports.requireType(cls.module, "SortedMap");
								"SortedMap<" + of(params[1]) + ">";
							case StringKey:
								imports.requireType(cls.module, "SortedMapStr");
								"SortedMapStr<" + of(params[1]) + ">";
							case StructKey(def, _):
								imports.requireType(cls.module, "SortedMapObj");
								"SortedMapObj<" + of(params[0]) + ", " + of(params[1]) + ">";
						}
					case "std.SortedMapBuilder":
						switch(classifyKey(params[0])) {
							case IntKey:
								imports.requireType(cls.module, "SortedMapBuilder");
								"SortedMapBuilder<" + of(params[1]) + ">";
							case StringKey:
								imports.requireType(cls.module, "SortedMapStrBuilder");
								"SortedMapStrBuilder<" + of(params[1]) + ">";
							case StructKey(def, _):
								imports.requireType(cls.module, "SortedMapObjBuilder");
								"SortedMapObjBuilder<" + of(params[0]) + ", " + of(params[1]) + ">";
						}
					case "std.SortedSet":
						switch(classifyKey(params[0])) {
							case IntKey:
								imports.requireType(cls.module, "SortedSet");
								"SortedSet";
							case StringKey:
								imports.requireType(cls.module, "SortedSetStr");
								"SortedSetStr";
							case StructKey(def, _):
								imports.requireType(cls.module, "SortedSetObj");
								"SortedSetObj<" + of(params[0]) + ">";
						}
					case "std.SortedSetBuilder":
						switch(classifyKey(params[0])) {
							case IntKey:
								imports.requireType(cls.module, "SortedSetBuilder");
								"SortedSetBuilder";
							case StringKey:
								imports.requireType(cls.module, "SortedSetStrBuilder");
								"SortedSetStrBuilder";
							case StructKey(def, _):
								imports.requireType(cls.module, "SortedSetObjBuilder");
								"SortedSetObjBuilder<" + of(params[0]) + ">";
						}
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

	public static function classifyKey(t: Null<Type>, ?pos: haxe.macro.Expr.Position): KeyDomain {
		if(t == null) {
			final p = pos != null ? pos : Context.currentPos();
			Context.error("sorted keyed tables support Int, String, and structure keys in this implementation", p);
			return IntKey;
		}
		final p = pos != null ? pos : Context.currentPos();
		return switch(t) {
			case TAbstract(a, _):
				if(a.get().name == "Int") {
					IntKey;
				} else {
					Context.error("sorted keyed tables support Int, String, and structure keys in this implementation", p);
					IntKey;
				}
			case TInst(c, _):
				if(c.get().name == "String") {
					StringKey;
				} else {
					Context.error("sorted keyed tables support Int, String, and structure keys in this implementation", p);
					IntKey;
				}
			case TType(defRef, _):
				final def = defRef.get();
				final fields = validateStructDef(def, p, [def.name]);
				StructKey(def, fields);
			case TLazy(f):
				classifyKey(f(), p);
			case _:
				Context.error("sorted keyed tables support Int, String, and structure keys in this implementation", p);
				IntKey;
		}
	}

	static function validateStructDef(def: DefType, pos: haxe.macro.Expr.Position, visited: Array<String>): Array<ClassField> {
		return switch(def.type) {
			case TAnonymous(anonRef):
				final fields = anonRef.get().fields.copy();
				fields.sort((a, b) -> Reflect.compare(Context.getPosInfos(a.pos).min, Context.getPosInfos(b.pos).min));
				for(f in fields) {
					validateFieldType(f.type, f.pos, visited);
				}
				fields;
			case TType(innerDefRef, _):
				validateStructDef(innerDefRef.get(), pos, visited);
			case _:
				Context.error("sorted keyed tables support Int, String, and structure keys in this implementation", pos);
				[];
		}
	}

	static function validateFieldType(t: Type, pos: haxe.macro.Expr.Position, visited: Array<String>): Void {
		switch(t) {
			case TAbstract(a, _):
				final name = a.get().name;
				if(name == "Int" || name == "Bool") {
					return;
				}
				Context.error("structure key fields must be Int, Bool, String, or a nested structure", pos);
			case TInst(c, _):
				if(c.get().name == "String") {
					return;
				}
				Context.error("structure key fields must be Int, Bool, String, or a nested structure", pos);
			case TType(dRef, _):
				final def = dRef.get();
				if(visited.indexOf(def.name) >= 0) {
					Context.error("structure key fields must be Int, Bool, String, or a nested structure", pos);
					return;
				}
				switch(def.type) {
					case TAnonymous(_):
						final nextVisited = visited.copy();
						nextVisited.push(def.name);
						validateStructDef(def, pos, nextVisited);
					case TType(innerRef, _):
						validateFieldType(def.type, pos, visited);
					case _:
						Context.error("structure key fields must be Int, Bool, String, or a nested structure", pos);
				}
			case TLazy(f):
				validateFieldType(f(), pos, visited);
			case _:
				Context.error("structure key fields must be Int, Bool, String, or a nested structure", pos);
		}
	}

	function fail(t: Type): String {
		Context.error("type has no Kotlin lowering in the translatable subset: " + Std.string(t), Context.currentPos());
		return null;
	}
}
#end
