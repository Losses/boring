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
		// A type parameter renders as its bare name; parameter
		// positions borrow it, the same rule String follows. The
		// generic runtime tables are the only source of these.
		if(isTypeParam(t)) {
			final name = switch(Context.follow(t)) {
				case TInst(c, _): c.get().name;
				case _: "";
			};
			return isParam ? "&" + name : name;
		}
		return switch(t) {
			case TAbstract(a, params):
				final abs = a.get();
				if(ValueTypeSupport.isMarkedAbstract(abs)) {
					imports.requireType(abs.module, abs.name);
					abs.name;
				} else switch(pathOf(abs.pack, abs.name)) {
					// Business modules keep haxe Int unsigned: the subset
					// domain is non-negative. Resident runtime modules
					// render Int as i32 because their contracts carry
					// signed values (negative slice bounds, the -1
					// no-previous sentinel); the call boundary casts
					// between the two conventions (RuntimeResidents).
					case "Int": RuntimeResidents.isResident(imports.selfModule) ? "i32" : "u32";
					// The module-level precision switch selects the Float
					// width for the whole compilation (feature spec 23).
					case "Float": FloatPrecision.isF32() ? "f32" : "f64";
					case "Bool": "bool";
					case "Void": "()";
					case "Null": "Option<" + of(params[0]) + ">";
					case "haxe.ds.Map" if(params.length == 2):
						imports.require("std::collections::HashMap");
						"HashMap<" + of(params[0]) + ", " + of(params[1]) + ">";
					case "std.ReadOnlyArray" | "ReadOnlyArray":
						isParam ? "&[" + of(params[0]) + "]" : "Vec<" + of(params[0]) + ">";
					case "haxe.Int64":
						"i64";
					case _: of(abs.type, isParam);
				}
			case TInst(c, params):
				final cls = c.get();
				switch(pathOf(cls.pack, cls.name)) {
					case "String": isParam ? "&str" : "String";
					// The buffer holds UTF-16 units; the pairing checks of
					// stdlib/08 need the raw units, and String could not
					// store an unpaired lead.
					case "std.StringBuf" | "StringBuf": isParam ? "&mut Vec<u16>" : "Vec<u16>";
					case "Array":
						isParam ? "&mut [" + of(params[0]) + "]" : "Vec<" + of(params[0]) + ">";
					case "haxe.io.Bytes":
						isParam ? "&[u8]" : "Vec<u8>";
					case "haxe.io.BytesBuffer":
						imports.requireType(cls.module, "BytesBuffer");
						"BytesBuffer";
					// The sorted externs lower onto the generic tables of
					// the runtime.SortedTable resident on every key
					// domain; the comparator bound at the builder site
					// carries the domain (docs/specs/stdlib/07).
					case "std.SortedMap":
						imports.requireType("std.SortedMap", "SortedMapTable");
						"SortedMapTable<" + of(params[0]) + ", " + of(params[1]) + ">";
					case "std.SortedMapBuilder":
						imports.requireType("std.SortedMapBuilder", "SortedMapTableBuilder");
						"SortedMapTableBuilder<" + of(params[0]) + ", " + of(params[1]) + ">";
					case "std.SortedSet":
						imports.requireType("std.SortedSet", "SortedSetTable");
						"SortedSetTable<" + of(params[0]) + ">";
					case "std.SortedSetBuilder":
						imports.requireType("std.SortedSetBuilder", "SortedSetTableBuilder");
						"SortedSetTableBuilder<" + of(params[0]) + ">";
					case _:
						imports.requireType(cls.module, cls.name);
						// Generic classes carry their type arguments; the
						// resident runtime tables are the source of these.
						params.length > 0
							? cls.name + "<" + [for(p in params) of(p)].join(", ") + ">"
							: cls.name;
				}
			case TType(def, params):
				final d = def.get();
				if(d.pack.join(".") == "haxe.io" && d.name == "Bytes") {
					isParam ? "&[u8]" : "Vec<u8>";
				} else if(d.pack.length == 0 && d.name == "Map" && params.length == 2) {
					imports.require("std::collections::HashMap");
					"HashMap<" + of(params[0]) + ", " + of(params[1]) + ">";
				} else if(RuntimeResidents.isResident(d.module)) {
					// Resident typedefs name function types for the
					// TypeScript alias; the Rust lane renders the
					// underlying fn type with the reference-site
					// arguments applied.
					of(haxe.macro.TypeTools.applyTypeParameters(d.type, d.params, params));
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
				"fn(" + [for(arg in args) of(arg.t, true)].join(", ") + ") -> " + of(ret, false);
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

	public static function isTypeParam(t: Null<Type>): Bool {
		if(t == null) {
			return false;
		}
		// Null<X> wraps X; Context.follow would strip the wrapper and
		// misreport the wrapped type as the parameter itself.
		switch(t) {
			case TAbstract(a, _) if(a.get().name == "Null"):
				return false;
			case _:
		}
		return switch(Context.follow(t)) {
			case TInst(c, _):
				switch(c.get().kind) {
					case KTypeParameter(_): true;
					case _: false;
				}
			case _: false;
		};
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
