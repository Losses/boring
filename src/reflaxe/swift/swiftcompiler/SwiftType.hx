package swiftcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;

enum SwiftKeyDomain {
	SwiftIntKey;
	SwiftStringKey;
	SwiftStructKey(def: DefType, fields: Array<ClassField>);
	SwiftDataClassKey(cls: ClassType, fields: Array<ClassField>);
}

/**
	Type mapping from the translatable Haxe subset to Swift, per
	docs/specs/features/07-numeric-tower.md and the stdlib rulings: Int is Int32 and
	Float is Double (numbers ruling), haxe.io.Bytes is the byte array
	(stdlib/01), haxe.io.BytesBuffer is the runtime growth class
	(stdlib/02), ReadOnlyArray is a let-bound Array (features/18). The
	resident string ABI (docs/specs/features/08-strings-and-unicode.md) renders String as Array<UInt16>
	inside resident modules; business modules keep native String and
	convert once at the resident boundary.
**/
class SwiftType {

	final imports: SwiftImports;

	/** Resident modules render String as the unit array of the runtime ABI. */
	public final resident: Bool;

	public function new(imports: SwiftImports) {
		this.imports = imports;
		this.resident = RuntimeResidents.isResident(imports.selfModule);
	}

	public function of(t: Null<Type>): String {
		if(t == null) {
			return "Void";
		}
		return switch(t) {
			case TAbstract(a, params):
				final abs = a.get();
				if(ValueTypeSupport.isMarkedAbstract(abs)) {
					abs.name;
				} else switch(pathOf(abs.pack, abs.name)) {
					case "Int": "Int32";
					// The f32 configuration maps the module real onto the native
					// binary32 type (feature spec 23).
					case "Float": FloatPrecision.isF32() ? "Float" : "Double";
					case "Bool": "Bool";
					case "Void": "Void";
					case "Null": wrapOptional(of(params[0]));
					case "haxe.ds.Map" if(params.length == 2): "[" + of(params[0]) + ": " + of(params[1]) + "]";
					case "std.ReadOnlyArray": "[" + of(params[0]) + "]";
					case "haxe.Int64": "Int64";
					case _: of(abs.type);
				}
			case TInst(c, params):
				final cls = c.get();
				switch(pathOf(cls.pack, cls.name)) {
					case "String": resident ? "[UInt16]" : "String";
					case "std.StringBuf" | "StringBuf": "[UInt16]";
					case "Array": "[" + of(params[0]) + "]";
					case "haxe.io.Bytes": "[UInt8]";
					case "haxe.io.BytesBuffer":
						imports.runtime("BytesBuffer");
						"BytesBuffer";
					case "std.SortedMap":
						imports.runtime("SortedMapTable");
						"SortedMapTable<" + of(params[0]) + ", " + of(params[1]) + ">";
					case "std.SortedMapBuilder":
						imports.runtime("SortedMapTableBuilder");
						"SortedMapTableBuilder<" + of(params[0]) + ", " + of(params[1]) + ">";
					case "std.SortedSet":
						imports.runtime("SortedSetTable");
						"SortedSetTable<" + of(params[0]) + ">";
					case "std.SortedSetBuilder":
						imports.runtime("SortedSetTableBuilder");
						"SortedSetTableBuilder<" + of(params[0]) + ">";
					case _:
						imports.value(cls.module, cls.name);
						// A generic class referenced with its arguments
						// carries them; Swift binds the bare name to
						// <Any, Any>, so the arguments always render.
						params.length > 0
							? cls.name + "<" + [for(p in params) of(p)].join(", ") + ">"
							: cls.name;
				}
			case TType(def, params):
				final d = def.get();
				if(d.pack.join(".") == "haxe.io" && d.name == "Bytes") {
					"[UInt8]";
				} else if(d.pack.length == 0 && d.name == "Map" && params.length == 2) {
					"[" + of(params[0]) + ": " + of(params[1]) + "]";
				} else if(RuntimeResidents.isResident(d.module) && params.length > 0) {
					// A resident named function type expands inline with its
					// arguments applied; Swift typealiases carry no generic
					// parameters here, so the function type renders directly.
					ofSubstituted(d.type, d.params, params);
				} else if(params.length == 0) {
					imports.type(d.module, d.name);
					d.name;
				} else {
					fail(t);
				}
			case TEnum(e, _):
				final en = e.get();
				imports.type(en.module, en.name);
				en.name;
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

	/**
		Renders a type with its type parameters replaced by applied
		arguments: the comparator alias of the sorted-table resident
		reaches its fields as a typedef applied to the class parameters.
	**/
	function ofSubstituted(t: Type, params: Array<TypeParameter>, args: Array<Type>): String {
		return switch(t) {
			case TAbstract(a, params2):
				final abs = a.get();
				for(i in 0...params.length) {
					if(params[i].name == abs.name) {
						return of(args[i]);
					}
				}
				switch(pathOf(abs.pack, abs.name)) {
					case "Int": "Int32";
					// The f32 configuration maps the module real onto the native
					// binary32 type (feature spec 23).
					case "Float": FloatPrecision.isF32() ? "Float" : "Double";
					case "Bool": "Bool";
					case "Void": "Void";
					case "Null": wrapOptional(ofSubstituted(params2[0], params, args));
					case "std.ReadOnlyArray": "[" + ofSubstituted(params2[0], params, args) + "]";
					case _: ofSubstituted(abs.type, params, args);
				}
			case TInst(c, params2):
				final cls = c.get();
				switch(pathOf(cls.pack, cls.name)) {
					case "String": resident ? "[UInt16]" : "String";
					case "std.StringBuf" | "StringBuf": "[UInt16]";
					case "Array": "[" + ofSubstituted(params2[0], params, args) + "]";
					case "haxe.io.Bytes": "[UInt8]";
					case _:
						for(i in 0...params.length) {
							if(params[i].name == cls.name) {
								return of(args[i]);
							}
						}
						switch(cls.kind) {
							case KTypeParameter(_): of(args[resolveParam(params, cls.name)]);
							case _: cls.name;
						}
				}
			case TType(def, params2):
				final d = def.get();
				if(RuntimeResidents.isResident(d.module) && params2.length > 0) {
					ofSubstituted(d.type, d.params, [for(p in params2) substituteType(p, params, args)]);
				} else if(params2.length == 0) {
					imports.type(d.module, d.name);
					d.name;
				} else {
					fail(t);
				}
			case TEnum(e, _):
				final en = e.get();
				imports.type(en.module, en.name);
				en.name;
			case TFun(args2, ret):
				"(" + [for(arg in args2) ofSubstituted(arg.t, params, args)].join(", ") + ") -> " + ofSubstituted(ret, params, args);
			case TLazy(f): ofSubstituted(f(), params, args);
			case _: fail(t);
		}
	}

	static function resolveParam(params: Array<TypeParameter>, name: String): Int {
		for(i in 0...params.length) {
			if(params[i].name == name) {
				return i;
			}
		}
		return 0;
	}

	/**
		Type parameter substitution, the structure-preserving counterpart
		of `ofSubstituted`: rebuilds a type with its parameters replaced
		by applied arguments so a nested alias application carries real
		types, with no rendered-text substitution.
	**/
	static function substituteType(t: Type, params: Array<TypeParameter>, args: Array<Type>): Type {
		return switch(t) {
			case TAbstract(a, ps):
				final abs = a.get();
				for(i in 0...params.length) {
					if(params[i].name == abs.name) {
						return args[i];
					}
				}
				TAbstract(a, [for(p in ps) substituteType(p, params, args)]);
			case TInst(c, ps):
				final cls = c.get();
				switch(cls.kind) {
					case KTypeParameter(_):
						args[resolveParam(params, cls.name)];
					case _:
						TInst(c, [for(p in ps) substituteType(p, params, args)]);
				}
			case TType(d, ps):
				TType(d, [for(p in ps) substituteType(p, params, args)]);
			case TEnum(e, ps):
				TEnum(e, [for(p in ps) substituteType(p, params, args)]);
			case TFun(fargs, ret):
				TFun([for(a in fargs) {name: a.name, t: substituteType(a.t, params, args), opt: a.opt}], substituteType(ret, params, args));
			case TLazy(f):
				substituteType(f(), params, args);
			case _:
				t;
		}
	}

	/**
		Optional rendering: a nested optional never occurs in the subset,
		but the spelled-out form keeps the shape total. Optionals of
		function types parenthesize.
	**/
	function wrapOptional(inner: String): String {
		return inner + "?";
	}

	function pathOf(pack: Array<String>, name: String): String {
		return pack.length == 0 ? name : pack.join(".") + "." + name;
	}

	public static function classifyKey(t: Null<Type>, ?pos: haxe.macro.Expr.Position): SwiftKeyDomain {
		if(t == null) {
			final p = pos != null ? pos : Context.currentPos();
			Context.error("sorted keyed tables support Int, String, structure, and dataClass keys in this implementation", p);
			return SwiftIntKey;
		}
		final p = pos != null ? pos : Context.currentPos();
		return switch(t) {
			case TAbstract(a, _):
				if(a.get().name == "Int") {
					SwiftIntKey;
				} else {
					Context.error("sorted keyed tables support Int, String, structure, and dataClass keys in this implementation", p);
					SwiftIntKey;
				}
			case TInst(c, _):
				final cls = c.get();
				if(cls.name == "String") {
					SwiftStringKey;
				} else if(cls.meta.has(":dataClass")) {
					final fields = [for(f in cls.fields.get()) if(switch(f.kind) { case FVar(_, _): true; case _: false; }) f];
					for(f in fields) validateDataClassField(cls, f, f.name);
					SwiftDataClassKey(cls, fields);
				} else {
					Context.error("sorted keyed tables support Int, String, structure, and dataClass keys in this implementation", p);
					SwiftIntKey;
				}
			case TType(defRef, _):
				final def = defRef.get();
				final fields = validateStructDef(def, p, [def.name]);
				SwiftStructKey(def, fields);
			case TLazy(f):
				classifyKey(f(), p);
			case _:
				Context.error("sorted keyed tables support Int, String, structure, and dataClass keys in this implementation", p);
				SwiftIntKey;
		}
	}

	static function validateDataClassField(cls: ClassType, field: ClassField, path: String): Void {
		if(!isDataClassFieldKey(field.type)) Context.error("dataClass key " + cls.name + " field " + path + " has unsupported type " + field.type, field.pos);
		if(switch(Context.follow(field.type)) { case TInst(c, _) if(c.get().meta.has(":dataClass")): true; case _: false; }) {
			final inner = switch(Context.follow(field.type)) { case TInst(c, _): c.get(); case _: null; };
			if(inner != null) for(f in inner.fields.get()) if(switch(f.kind) { case FVar(_, _): true; case _: false; }) validateDataClassField(inner, f, path + "." + f.name);
		}
	}

	static function isDataClassFieldKey(t: Type): Bool {
		return switch(t) {
			case TAbstract(a, _): a.get().name == "Int";
			case TEnum(_, _): true;
			case TInst(c, _): c.get().name == "String" || c.get().meta.has(":dataClass");
			case TLazy(f): isDataClassFieldKey(f());
			case _: switch(Context.follow(t)) {
				case TAbstract(a, _): a.get().name == "Int";
				case TEnum(_, _): true;
				case TInst(c, _): c.get().name == "String" || c.get().meta.has(":dataClass");
				case _: false;
			};
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
				Context.error("sorted keyed tables support Int, String, structure, and dataClass keys in this implementation", pos);
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
		Context.error("type has no Swift lowering in the translatable subset: " + Std.string(t), Context.currentPos());
		return null;
	}
}
#end
