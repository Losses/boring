package rustcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;

enum KeyDomain {
	IntKey;
	StringKey;
	StructKey(def: DefType, fields: Array<ClassField>);
}

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
					case "Null": "Option<" + of(params[0]) + ">";
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
					case "std.SortedMap":
						switch(classifyKey(params[0])) {
							case IntKey:
								imports.requireType("std.SortedMap", "SortedMap");
								"SortedMap<" + of(params[1]) + ">";
							case StringKey:
								imports.requireType("std.SortedMap", "SortedMapStr");
								"SortedMapStr<" + of(params[1]) + ">";
							case StructKey(def, _):
								imports.requireType("std.SortedMap", "SortedMapByKey");
								"SortedMapByKey<" + of(params[0]) + ", " + of(params[1]) + ">";
						}
					case "std.SortedMapBuilder":
						switch(classifyKey(params[0])) {
							case IntKey:
								imports.requireType("std.SortedMapBuilder", "SortedMapBuilder");
								"SortedMapBuilder<" + of(params[1]) + ">";
							case StringKey:
								imports.requireType("std.SortedMapBuilder", "SortedMapStrBuilder");
								"SortedMapStrBuilder<" + of(params[1]) + ">";
							case StructKey(def, _):
								imports.requireType("std.SortedMapBuilder", "SortedMapByKeyBuilder");
								"SortedMapByKeyBuilder<" + of(params[0]) + ", " + of(params[1]) + ">";
						}
					case "std.SortedSet":
						switch(classifyKey(params[0])) {
							case IntKey:
								imports.requireType("std.SortedSet", "SortedSet");
								"SortedSet";
							case StringKey:
								imports.requireType("std.SortedSet", "SortedSetStr");
								"SortedSetStr";
							case StructKey(def, _):
								imports.requireType("std.SortedSet", "SortedSetByKey");
								"SortedSetByKey<" + of(params[0]) + ">";
						}
					case "std.SortedSetBuilder":
						switch(classifyKey(params[0])) {
							case IntKey:
								imports.requireType("std.SortedSetBuilder", "SortedSetBuilder");
								"SortedSetBuilder";
							case StringKey:
								imports.requireType("std.SortedSetBuilder", "SortedSetStrBuilder");
								"SortedSetStrBuilder";
							case StructKey(def, _):
								imports.requireType("std.SortedSetBuilder", "SortedSetByKeyBuilder");
								"SortedSetByKeyBuilder<" + of(params[0]) + ">";
						}
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
				imports.requireType(en.module, en.name);
				en.name;
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
		Context.error("type has no Rust lowering in the translatable subset: " + Std.string(t), Context.currentPos());
		return null;
	}
}
#end
