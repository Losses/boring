package dartcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;

enum DartKeyDomain {
	DartIntKey;
	DartStringKey;
	DartStructKey(def: DefType, fields: Array<ClassField>);
}

/**
	Type mapping from the translatable Haxe subset to Dart, per
	docs/specs/stdlib/06-std-modules.md and the stdlib rulings: Int is `int` and
	Float is `double` (numbers ruling; the VM integer is a 64-bit machine
	word, wider than the i32 domain exactly as `number` is on the
	TypeScript lane), haxe.io.Bytes is `List<int>` (stdlib/01),
	haxe.io.BytesBuffer erases to the same list (stdlib/02), String is
	native `String` on business modules and residents alike because the
	language stores UTF-16 natively, and ReadOnlyArray erases to the
	`List` it wraps (features/18). Sorted tables keep the resident
	generated classes of runtime.SortedTable.
**/
class DartType {

	final imports: DartImports;

	public function new(imports: DartImports) {
		this.imports = imports;
	}

	public function of(t: Null<Type>): String {
		if(t == null) {
			return "void";
		}
		return switch(t) {
			case TAbstract(a, params):
				final abs = a.get();
				if(ValueTypeSupport.isMarkedAbstract(abs)) {
					final prefix = imports.type(abs.module, abs.name);
					prefix.length > 0 ? prefix + "." + abs.name : abs.name;
				} else switch(pathOf(abs.pack, abs.name)) {
					case "Int": "int";
					case "Float": "double";
					case "Bool": "bool";
					case "Void": "void";
					case "Null": wrapOptional(of(params[0]));
					case "haxe.ds.Map" if(params.length == 2): "Map<" + of(params[0]) + ", " + of(params[1]) + ">";
					case "std.ReadOnlyArray": "List<" + of(params[0]) + ">";
					case _: of(abs.type);
				}
			case TInst(c, params):
				final cls = c.get();
				switch(pathOf(cls.pack, cls.name)) {
					case "String": "String";
					case "std.StringBuf" | "StringBuf": "List<int>";
					case "Array": "List<" + of(params[0]) + ">";
					case "haxe.io.Bytes": "List<int>";
					case "haxe.io.BytesBuffer": "List<int>";
					case "std.SortedMap": runtimeTypeRef("SortedMapTable", params);
					case "std.SortedMapBuilder": runtimeTypeRef("SortedMapTableBuilder", params);
					case "std.SortedSet": runtimeTypeRef("SortedSetTable", params);
					case "std.SortedSetBuilder": runtimeTypeRef("SortedSetTableBuilder", params);
					case _:
						final prefix = imports.value(cls.module, cls.name);
						final head = prefix.length > 0 ? prefix + "." + cls.name : cls.name;
						params.length > 0 ? head + "<" + [for(p in params) of(p)].join(", ") + ">" : head;
				}
			case TType(def, params):
				final d = def.get();
				if(d.pack.join(".") == "haxe.io" && d.name == "Bytes") {
					"List<int>";
				} else if(d.pack.length == 0 && d.name == "Map" && params.length == 2) {
					"Map<" + of(params[0]) + ", " + of(params[1]) + ">";
				} else if(RuntimeResidents.isResident(d.module) && params.length > 0) {
					// A resident named function type expands inline with its
					// arguments applied; the comparator alias of the sorted
					// tables reaches its fields this way.
					ofSubstituted(d.type, d.params, params);
				} else if(params.length == 0) {
					final prefix = imports.type(d.module, d.name);
					prefix.length > 0 ? prefix + "." + d.name : d.name;
				} else {
					fail(t);
				}
			case TEnum(e, params):
				final en = e.get();
				final prefix = imports.type(en.module, en.name);
				final head = prefix.length > 0 ? prefix + "." + en.name : en.name;
				params.length > 0 ? head + "<" + [for(p in params) of(p)].join(", ") + ">" : head;
			case TFun(args, ret):
				// Dart spells a function type with the return first.
				of(ret) + " Function(" + [for(arg in args) of(arg.t)].join(", ") + ")";
			case TAnonymous(_):
				Context.error("anonymous structure types must be named typedefs before translation", Context.currentPos());
				null;
			case TDynamic(_) | TMono(_):
				fail(t);
			case TLazy(f): of(f());
		}
	}

	/**
		A type of the runtime library with its arguments applied. The
		prefix registers the runtime reference: business files import the
		runtime library as `runtime`, resident files already live in it.
	**/
	function runtimeTypeRef(name: String, params: Array<Type>): String {
		final prefix = imports.runtimePrefix();
		final head = prefix.length > 0 ? prefix + "." + name : name;
		return head + "<" + [for(p in params) of(p)].join(", ") + ">";
	}

	/**
		Renders a type with its type parameters replaced by applied
		arguments, the resident-alias twin of `of`: the comparator alias
		of the sorted-table resident reaches its fields as a typedef
		applied to the class parameters.
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
					case "Int": "int";
					case "Float": "double";
					case "Bool": "bool";
					case "Void": "void";
					case "Null": wrapOptional(ofSubstituted(params2[0], params, args));
					case "std.ReadOnlyArray": "List<" + ofSubstituted(params2[0], params, args) + ">";
					case _: ofSubstituted(abs.type, params, args);
				}
			case TInst(c, params2):
				final cls = c.get();
				switch(pathOf(cls.pack, cls.name)) {
					case "String": "String";
					case "std.StringBuf" | "StringBuf": "List<int>";
					case "Array": "List<" + ofSubstituted(params2[0], params, args) + ">";
					case "haxe.io.Bytes": "List<int>";
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
				if(d.pack.join(".") == "haxe.io" && d.name == "Bytes") {
					"List<int>";
				} else if(d.pack.join(".") == "std" && d.name == "ReadOnlyArray") {
					"List<" + ofSubstituted(params2[0], params, args) + ">";
				} else if(RuntimeResidents.isResident(d.module) && params2.length > 0) {
					ofSubstituted(d.type, d.params, [for(p in params2) substituteType(p, params, args)]);
				} else if(params2.length == 0) {
					d.name;
				} else {
					fail(t);
				}
			case TEnum(e, _):
				e.get().name;
			case TFun(args2, ret):
				// Dart spells a function type with the return first.
				ofSubstituted(ret, params, args) + " Function(" + [for(arg in args2) ofSubstituted(arg.t, params, args)].join(", ") + ")";
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
		Type-level parameter substitution, the structure-preserving twin
		of `ofSubstituted`: rebuilds a type with its parameters replaced
		by applied arguments so a nested alias application carries real
		types, not rendered text.
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

	/** Optional rendering: a trailing question mark on the whole type. */
	function wrapOptional(inner: String): String {
		return inner + "?";
	}

	function pathOf(pack: Array<String>, name: String): String {
		return pack.length == 0 ? name : pack.join(".") + "." + name;
	}

	public static function classifyKey(t: Null<Type>, ?pos: haxe.macro.Expr.Position): DartKeyDomain {
		if(t == null) {
			final p = pos != null ? pos : Context.currentPos();
			Context.error("sorted keyed tables support Int, String, and structure keys in this implementation", p);
			return DartIntKey;
		}
		final p = pos != null ? pos : Context.currentPos();
		return switch(t) {
			case TAbstract(a, _):
				if(a.get().name == "Int") {
					DartIntKey;
				} else {
					Context.error("sorted keyed tables support Int, String, and structure keys in this implementation", p);
					DartIntKey;
				}
			case TInst(c, _):
				if(c.get().name == "String") {
					DartStringKey;
				} else {
					Context.error("sorted keyed tables support Int, String, and structure keys in this implementation", p);
					DartStringKey;
				}
			case TType(defRef, _):
				final def = defRef.get();
				final fields = validateStructDef(def, p, [def.name]);
				DartStructKey(def, fields);
			case TLazy(f):
				classifyKey(f(), p);
			case _:
				Context.error("sorted keyed tables support Int, String, and structure keys in this implementation", p);
				DartIntKey;
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
		Context.error("type has no Dart lowering in the translatable subset: " + Std.string(t), Context.currentPos());
		return null;
	}
}
#end
