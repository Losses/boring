package swiftcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.data.ClassFuncData;
import reflaxe.data.ClassVarData;
import reflaxe.data.EnumOptionData;

/**
	Declaration lowering: classes, variant enums, and record typedefs
	(docs/specs/targets/swift.md). One SwiftDecl instance owns the
	per-module emission context (imports, types, expression state) so
	every declaration in the same Haxe module lands in one Swift file.
	The whole tree shares one Swift module, so no import block renders;
	what the context tracks is runtime usage and the resident ABI mode.
**/
class SwiftDecl {
	final imports: SwiftImports;
	final types: SwiftType;
	final expr: SwiftExpr;

	public function new(selfModule: String) {
		this.imports = new SwiftImports(selfModule);
		this.types = new SwiftType(imports);
		this.expr = new SwiftExpr(imports, types);
	}

	/** Whether this module references any runtime-package symbol. */
	public function usesRuntime(): Bool {
		return imports.usesRuntime();
	}

	/** Whether this module references any test-host symbol. */
	public function usesRuntimeTest(): Bool {
		return imports.usesRuntimeTest();
	}

	public function topLevelStatements(e: TypedExpr): String {
		return expr.topLevelStatements(e);
	}

	public function rawExpression(e: TypedExpr): String {
		return expr.rawExpression(e);
	}

	// ------------------------------------------------------------------
	// Classes
	// ------------------------------------------------------------------

	public function classDecl(cls: ClassType, varFields: Array<ClassVarData>, funcFields: Array<ClassFuncData>): String {
		if(cls.isInterface) {
			// An interface lowers to a protocol; the implementing class
			// names it in its conformance clause.
			final lines: Array<String> = ["protocol " + cls.name + " {"];
			for(f in funcFields) {
				lines.push("    func " + f.field.name + paramList(cls, f) + " -> " + types.of(f.ret));
			}
			lines.push("}");
			return lines.join("\n");
		}

		if(cls.superClass != null) {
			final parent = cls.superClass.t.get();
			final parentPath = parent.pack.length == 0 ? parent.name : parent.pack.join(".") + "." + parent.name;
			if(parentPath != "haxe.Exception") {
				Context.error("super class has no Swift lowering in the subset: " + parentPath, cls.pos);
			}
		}

		final module = cls.module;
		final staticsOnly = isStaticsOnly(varFields, funcFields);
		final lines: Array<String> = [];

		// A statics-only class lowers to a case-less enum namespace
		// because Swift has no file-level static members; an instance
		// class lowers to a final class (the samples carry no
		// subclassing outside haxe.Exception).
		final classParams = cls.params.length > 0 ? "<" + [for(p in cls.params) p.name].join(", ") + ">" : "";
		if(staticsOnly) {
			lines.push("enum " + cls.name + classParams + " {");
		} else {
			final conformances: Array<String> = [];
			if(isException(cls)) {
				conformances.push("BoringException");
			}
			for(i in cls.interfaces) {
				conformances.push(i.t.get().name);
			}
			lines.push("final class " + cls.name + classParams + (conformances.length > 0 ? ": " + conformances.join(", ") : "") + " {");
		}

		// One blank line between members; none inside a member's body.
		for(v in varFields) {
			final decl = varDecl(module, v);
			if(decl.length == 0) {
				continue;
			}
			if(lines.length > 1) {
				lines.push("");
			}
			for(l in decl) {
				lines.push(l);
			}
		}
		for(f in funcFields) {
			if(lines.length > 1) {
				lines.push("");
			}
			// A computed property renders beside its accessor function
			// (feature spec 27).
			if(!f.isStatic && StringTools.startsWith(f.field.name, "get_")) {
				final propName = f.field.name.substring("get_".length);
				for(field in cls.fields.get()) {
					if(field.name == propName && isGetterOnlyProperty(field)) {
						for(l in propertyDecl(cls, field)) {
							lines.push(l);
						}
						lines.push("");
					}
				}
			}
			for(l in funcDecl(module, cls, f)) {
				lines.push(l);
			}
		}

		lines.push("}");
		return lines.join("\n");
	}

	static function isStaticsOnly(varFields: Array<ClassVarData>, funcFields: Array<ClassFuncData>): Bool {		for(v in varFields) {
			if(!v.isStatic) {
				return false;
			}
		}
		for(f in funcFields) {
			if(!f.isStatic) {
				return false;
			}
		}
		return true;
	}

	/** A class extending haxe.Exception is one of the features/06 exception classes. */
	static function isException(cls: ClassType): Bool {
		if(cls.superClass == null) {
			return false;
		}
		final parent = cls.superClass.t.get();
		final parentPath = parent.pack.length == 0 ? parent.name : parent.pack.join(".") + "." + parent.name;
		return parentPath == "haxe.Exception";
	}

	// ------------------------------------------------------------------
	// Record shape registry
	// ------------------------------------------------------------------

	/**
		Structure signature to the named record typedef of that shape.
		The typer leaves an object literal's own type anonymous even where
		unification matched a named typedef, so nominal lowering matches
		literals against typedefs through this signature.
	**/
	public static final structTypedefs: Map<String, Ref<DefType>> = [];

	/**
		Signature identifying an anonymous structure: its field names and
		types, sorted. Nominal lowering matches object literals against
		typedefs through this signature.
	**/
	public static function structureSignature(anon: Ref<AnonType>): String {
		final entries = [for(f in anon.get().fields) f.name + ":" + Std.string(f.type)];
		entries.sort(Reflect.compare);
		return entries.join(";");
	}

	/** Registers one record typedef; two names for one shape would make nominal matching ambiguous. */
	public static function registerStructTypedef(def: Ref<DefType>): Void {
		switch(def.get().type) {
			case TAnonymous(anon):
				final sig = structureSignature(anon);
				final existing = structTypedefs.get(sig);
				if(existing != null && (existing.get().name != def.get().name || existing.get().module != def.get().module)) {
					Context.error("typedefs " + existing.get().name + " and " + def.get().name + " share one anonymous structure shape", def.get().pos);
				}
				structTypedefs.set(sig, def);
			case _:
		}
	}

	function varDecl(module: String, v: ClassVarData): Array<String> {
		final field = v.field;
		if(v.isStatic && DataTableHelper.isDataTableField(field)) {
			final elems = DataTableHelper.getDataTableElements(field.expr());
			if(elems != null) {
				return ["    static let " + field.name + ": [Int32] = [" + renderDataTableElements(elems) + "]"];
			}
		}
		if(field.meta.has(":value")) {
			if(v.isStatic) {
				// Inline constants fold into their use sites as TConst.
				return [];
			}
			Context.error("instance field default has no lowering; assign it in the constructor", field.pos);
		}
		if(v.isStatic) {
			Context.error("mutable static field has no lowering in the subset", field.pos);
		}
		// A final Haxe field pins the reference, not the contents: an
		// array field still grows in place (the sorted builders), and a
		// Swift let array forbids that, so array fields stay var.
		final isArrayField = switch(field.type) {
			case TInst(c, _): c.get().name == "Array";
			case TLazy(f): switch(f()) {
				case TInst(c, _): c.get().name == "Array";
				case _: false;
			};
			case _: false;
		};
		final kw = isArrayField || !field.isFinal ? "var" : "let";
		// Private fields render with Swift's private marker (feature
		// spec 27); public fields keep the default internal visibility.
		final vis = field.isPublic ? "" : "private ";
		return ["    " + vis + kw + " " + field.name + ": " + types.of(field.type)];
	}

	/** A `var x(get, never)` field renders no storage on this target (feature spec 27). */
	function isGetterOnlyProperty(field: ClassField): Bool {
		switch(field.kind) {
			case FVar(read, write):
				return read.match(AccCall) && write.match(AccNever);
			case _:
				return false;
		}
	}

	/**
		A getter-only property renders as a computed property reading the
		standard accessor (feature spec 27). The typer lowers property
		reads to `get_x()` calls, so the computed property serves
		consuming Swift code.
	**/
	function propertyDecl(cls: ClassType, field: ClassField): Array<String> {
		final vis = field.isPublic ? "" : "private ";
		final getter = "get_" + field.name;
		return ["    " + vis + "var " + field.name + ": " + types.of(field.type) + " { " + getter + "() }"];
	}

	function renderDataTableElements(elems: Array<Int>): String {
		final formatted = [for(x in elems) (x >= 0 && x <= 9) ? Std.string(x) : "0x" + StringTools.hex(x).toLowerCase()];
		final chunks: Array<String> = [];
		var i = 0;
		while(i < formatted.length) {
			final end = Std.int(Math.min(i + 8, formatted.length));
			chunks.push("\n        " + formatted.slice(i, end).join(", "));
			i = end;
		}
		return chunks.join(",") + "\n    ";
	}

	/**
		One @:test function (features/19): a static throwing function on
		the module's test namespace. The runner entry that calls it lands
		in TestMain.swift.
	**/
	public function testFuncDecl(cls: ClassType, f: ClassFuncData): Array<String> {
		for(a in f.args) {
			expr.reserveName(a.name);
		}
		final throws = SwiftFallibility.isThrowing(cls.module, f.field.name, true) ? " throws" : "";
		final body = expr.functionBody(cls, f);
		return ["    static func " + f.field.name + "()" + throws + " -> Void {"].concat(body).concat(["    }"]);
	}

	/** Function declarations append the parameter shadows after the body scan. */
	function withParamShadows(head: Array<String>, body: Array<String>, args: Array<{name: String, ?tvar: Null<TVar>}>): Array<String> {
		return head.concat(expr.shadowMutatedParams(args)).concat(body);
	}

	function funcDecl(module: String, cls: ClassType, f: ClassFuncData): Array<String> {
		// Haxe types constructors as FMethod(MethNormal) with field name
		// "new"; the name is the constructor marker. Swift initializes
		// stored properties before the super call, the reverse of the
		// Haxe source order.
		if(f.field.name == "new") {
			for(a in f.args) {
				expr.reserveName(a.name);
			}
			final body = expr.constructorBody(cls, cls.name, f, isException(cls));
			// A throwing constructor declares throws (feature spec 27);
			// construction sites pick up the try marker from the
			// fallibility machinery.
			final ctorThrows = SwiftFallibility.isThrowing(module, "new", false) ? " throws" : "";
			return withParamShadows(["    init" + paramList(cls, f) + ctorThrows + " {"], body, cast f.args).concat(["    }"]);
		}
		for(a in f.args) {
			expr.reserveName(a.name);
		}
		final ret = types.of(f.ret);
		final stat = f.isStatic ? "static " : "";
		final throws = SwiftFallibility.isThrowing(module, f.field.name, f.isStatic) ? " throws" : "";
		// A method's own type parameters (the resident builders'
		// factory functions) render as method generics; the class's own
		// parameters stay in the class header only.
		final methodParams = collectMethodTypeParams(cls, f);
		final genericStr = methodParams.length > 0 ? "<" + methodParams.join(", ") + ">" : "";
		final body = decodeBoundaryBody(cls, f);
		final normLines = coalescingBodyNormalizationLines(cls, f);
		// Private functions render with Swift's private marker (feature
		// spec 27); public functions keep the default internal visibility.
		final vis = f.field.isPublic ? "" : "private ";
		final head = '    $stat$vis' + 'func ${f.field.name}$genericStr${paramList(cls, f)}$throws -> $ret {';
		return withParamShadows([head], normLines.concat(body), cast f.args).concat(["    }"]);
	}

	/**
		Parameter rendering: positional calls throughout, so every
		parameter takes the wildcard label. Function-typed parameters
		carry @escaping because the resident tables store their
		comparator.
	**/
	function paramList(cls: ClassType, f: ClassFuncData): String {
		return "(" + [for(a in f.args) {
			final coalescing = DefaultArgExpander.coalescingDefaultAt(cls, f.field.name, a.index);
			final readsParam = coalescing != null && DefaultArgExpander.coalescingReadsParamForParam(cls, f.field.name, a.name);
			final baseType = coalescing != null ? DefaultArgExpander.coalescingParameterType(coalescing, a.type) : a.type;
			// When the default reads an earlier parameter, Swift needs
			// an Optional type so the default value can be nil.
			final parameterType = readsParam ? makeOptional(baseType) : baseType;
			final escaping = switch(Context.follow(a.type)) {
				case TFun(_, _): "@escaping ";
				case _: "";
			};
			final defaultText = if (coalescing != null) {
				if (readsParam) " = nil" else " = " + expr.coalescingDefaultText(coalescing, a.type);
			} else "";
			"_ " + a.name + ": " + escaping + types.of(parameterType) + defaultText;
		}].join(", ") + ")";
	}

	/** Wraps a Haxe type in Null<T> to produce a Swift optional. */
	function makeOptional(t:Type):Type {
		final nullAbst = switch(Context.getType("Null")) {
			case TAbstract(a, _): a;
			case _: return t;
		};
		return TAbstract(nullAbst, [t]);
	}

	/**
		The names of a function's own type parameters, in first-use
		order over the signature. A generic method references its
		parameters as type-parameter classes; names owned by the
		enclosing class belong to the class header, not the method.
	**/
	function collectMethodTypeParams(cls: ClassType, f: ClassFuncData): Array<String> {
		final classParamNames = [for(p in cls.params) p.name];
		final found: Array<String> = [];
		collectTypeParamsInto(f.ret, classParamNames, found);
		for(a in f.args) {
			collectTypeParamsInto(a.type, classParamNames, found);
		}
		return found;
	}

	function collectTypeParamsInto(t: Null<Type>, skip: Array<String>, found: Array<String>): Void {
		if(t == null) {
			return;
		}
		switch(t) {
			case TInst(c, params):
				final cls = c.get();
				if(switch(cls.kind) {
					// Haxe 4.3 carries the parameter's constraints on
					// the kind constructor.
					case KTypeParameter(_): true;
					case _: false;
				}) {
					if(skip.indexOf(cls.name) < 0 && found.indexOf(cls.name) < 0) {
						found.push(cls.name);
					}
				}
				for(p in params) collectTypeParamsInto(p, skip, found);
			case TAbstract(_, params) | TType(_, params) | TEnum(_, params):
				for(p in params) collectTypeParamsInto(p, skip, found);
			case TFun(args, ret):
				for(arg in args) collectTypeParamsInto(arg.t, skip, found);
				collectTypeParamsInto(ret, skip, found);
			case TLazy(fun):
				collectTypeParamsInto(fun(), skip, found);
			case _:
		}
	}

	/**
		Body normalization lines for coalescing defaults that read
		earlier parameters. Swift cannot use a default argument
		expression that references other parameters, so the parameter
		takes `T? = nil` in the signature and the body assigns
		`p = p ?? E;` at entry.
	**/
	function coalescingBodyNormalizationLines(cls: ClassType, f: ClassFuncData): Array<String> {
		final out: Array<String> = [];
		for(a in f.args) {
			final coalescing = DefaultArgExpander.coalescingDefaultAt(cls, f.field.name, a.index);
			if(coalescing == null) continue;
			if(!DefaultArgExpander.coalescingReadsParamForParam(cls, f.field.name, a.name)) continue;
			final defaultText = expr.coalescingDefaultText(coalescing, a.type);
			// Swift function parameters are let constants; shadow as var.
			out.push("        var " + a.name + " = " + a.name + " ?? " + defaultText + ";");
		}
		return out;
	}

	/**
		features/18: a function returning ReadOnlyArray is a decode
		boundary. Array is a value type in Swift and a let binding
		freezes it structurally, so no freeze wrappers render; the flag
		only keeps the boundary visible to the expression layer.
	**/
	function decodeBoundaryBody(cls: ClassType, f: ClassFuncData): Array<String> {
		final boundary = switch(f.ret) {
			case TAbstract(a, _):
				final abs = a.get();
				abs.pack.join(".") == "std" && abs.name == "ReadOnlyArray";
			case _: false;
		}
		expr.setDecodeBoundary(boundary);
		final body = expr.functionBody(cls, f);
		expr.setDecodeBoundary(false);
		return body;
	}

	// ------------------------------------------------------------------
	// Variant enums (features/01)
	// ------------------------------------------------------------------

	public function enumDecl(en: EnumType, options: Array<EnumOptionData>): String {
		final sorted = options.copy();
		sorted.sort((a, b) -> Reflect.compare(a.field.index, b.field.index));
		var valueEnum = true;
		for(o in sorted) if(o.args.length > 0) valueEnum = false;
		if(valueEnum) {
			final lines = ['enum ${en.name}: String, CaseIterable, Equatable {'];
			for(o in sorted) lines.push('    case ${lowerFirst(o.name)} = "${o.name}"');
			lines.push("}");
			return lines.join("\n");
		}
		final lines: Array<String> = [
			// Equatable backs the construct comparisons the samples run
			// (`width == F64`); payload types of the subset (Int32,
			// String, nested enums) synthesize the conformance.
			"enum " + en.name + ": Equatable {"
		];
		for(o in sorted) {
			final caseName = lowerFirst(o.name);
			if(o.args.length == 0) {
				lines.push("    case " + caseName);
			} else {
				final payloads = [for(arg in o.args) arg.name + ": " + types.of(arg.type)].join(", ");
				lines.push("    case " + caseName + "(" + payloads + ")");
			}
		}
		lines.push("}");
		return lines.join("\n");
	}

	public static function lowerFirst(s: String): String {
		return s.charAt(0).toLowerCase() + s.substr(1);
	}

	// ------------------------------------------------------------------
	// Record typedefs (features/03, features/18)
	// ------------------------------------------------------------------

	public function typedefDecl(def: DefType): String {
		switch(def.type) {
			case TAnonymous(anonRef):
				final fields = anonRef.get().fields.copy();
				fields.sort((a, b) -> Reflect.compare(Context.getPosInfos(a.pos).min, Context.getPosInfos(b.pos).min));
				// Equatable backs the generated test assertions; the
				// field types of the subset (scalars, strings, arrays,
				// optionals, nested records) synthesize the conformance.
				final lines: Array<String> = ["struct " + def.name + ": Equatable {"];
				for(field in fields) {
					lines.push("    let " + field.name + ": " + types.of(field.type));
				}
				lines.push("}");
				if(isStructKeyCandidate(fields)) {
					return lines.join("\n") + "\n\n" + comparatorDecl(def, fields);
				}
				return lines.join("\n");
			case _:
				Context.error("typedef alias has no lowering; name the structure instead", def.pos);
				return null;
		}
	}

	/**
		The per-type key comparator stdlib/07 binds into sorted builders
		with structure keys. Integer fields subtract; Bool and String
		fields branch; nested structures delegate to their comparator.
		String fields compare through the unit-order helper because the
		native operators order by canonical equivalence.
	**/
	function comparatorDecl(def: DefType, fields: Array<ClassField>): String {
		final lines: Array<String> = [
			"func compare" + def.name + "(_ a: " + def.name + ", _ b: " + def.name + ") -> Int32 {"
		];
		for(f in fields) {
			switch(Context.follow(f.type)) {
				case TAbstract(a, _) if(a.get().name == "Int"):
					lines.push("    if a." + f.name + " != b." + f.name + " {");
					lines.push("        return a." + f.name + " - b." + f.name);
					lines.push("    }");
				case TAbstract(a, _) if(a.get().name == "Bool"):
					lines.push("    if a." + f.name + " != b." + f.name + " {");
					lines.push("        return a." + f.name + " ? 1 : -1");
					lines.push("    }");
				case TInst(c, _) if(c.get().name == "String"):
					lines.push("    if a." + f.name + " != b." + f.name + " {");
					lines.push("        return compareUnitOrder(a." + f.name + ", b." + f.name + ")");
					lines.push("    }");
				case _:
					switch(f.type) {
						case TType(innerDef, _):
							final inner = innerDef.get();
							final orderName = "order" + upperFirst(f.name);
							lines.push("    let " + orderName + " = compare" + inner.name + "(a." + f.name + ", b." + f.name + ")");
							lines.push("    if " + orderName + " != 0 {");
							lines.push("        return " + orderName);
							lines.push("    }");
						case _:
					}
			}
		}
		lines.push("    return 0");
		lines.push("}");
		return lines.join("\n");
	}

	static function upperFirst(s: String): String {
		return s.charAt(0).toUpperCase() + s.substr(1);
	}

	function isStructKeyCandidate(fields: Array<ClassField>): Bool {
		for(f in fields) {
			if(!isFieldKeyCandidate(f.type)) return false;
		}
		return true;
	}

	function isFieldKeyCandidate(t: Type): Bool {
		return switch(t) {
			case TAbstract(a, _):
				final n = a.get().name;
				n == "Int" || n == "Bool";
			case TInst(c, _):
				c.get().name == "String";
			case TType(d, _):
				switch(d.get().type) {
					case TAnonymous(anon):
						isStructKeyCandidate(anon.get().fields);
					case _: false;
				}
			case TLazy(fn):
				isFieldKeyCandidate(fn());
			case _: false;
		};
	}
}
#end
