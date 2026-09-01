package dartcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.data.ClassFuncData;
import reflaxe.data.ClassVarData;
import reflaxe.data.EnumOptionData;
import ValueTypeSupport;
import ValueTypeSupport.ValueTypeInfo;
import ValueTypeSupport.ValueTypeOperator;

/**
	Declaration lowering: classes, variant enums, and record typedefs
	(docs/specs/stdlib/06-std-modules.md). One DartDecl instance owns the
	per-module emission context (imports, types, expression state) so
	every declaration in the same Haxe module is written to one Dart library
	at `pack/module.dart`. Top-level names of the library are claimed
	through this instance so the flattened, nominal, and generated
	forms never collide.
**/
class DartDecl {
	public final imports: DartImports;
	final types: DartType;
	final expr: DartExpr;

	/** Top-level names already claimed in this library. */
	final topLevelNames: Map<String, Bool> = [];

	/** Whether any emitted equality compares a list field. */
	var seqEqualsNeeded = false;

	public function new(selfModule: String) {
		this.imports = new DartImports(selfModule);
		this.types = new DartType(imports);
		this.expr = new DartExpr(imports, types);
	}

	/** Whether this module references any runtime-package symbol. */
	public function usesRuntime(): Bool {
		return imports.usesRuntime();
	}

	/** Whether this module references any test-host symbol. */
	public function usesRuntimeTest(): Bool {
		return imports.usesRuntimeTest();
	}

	/** Whether this module needs the private list-equality helper. */
	public function needsSeqEquals(): Bool {
		return seqEqualsNeeded;
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
			// An interface lowers to an abstract class; the implementing
			// class names it in its implements clause.
			final lines: Array<String> = ["abstract class " + cls.name + classParamsOf(cls) + " {"];
			for(f in funcFields) {
				lines.push("  " + methodSignature(cls, f) + ";");
			}
			lines.push("}");
			return lines.join("\n");
		}

		if(cls.superClass != null) {
			final parent = cls.superClass.t.get();
			final parentPath = parent.pack.length == 0 ? parent.name : parent.pack.join(".") + "." + parent.name;
			if(parentPath != "haxe.Exception") {
				Context.error("super class has no Dart lowering in the subset: " + parentPath, cls.pos);
			}
		}

		final module = cls.module;
		final extractedFuncs = [for(f in funcFields) if(StaticFunctionMarkers.isMarked(f.field)) f];
		final ordinaryFuncs = [for(f in funcFields) if(!StaticFunctionMarkers.isMarked(f.field)) f];
		// One extension name covers every function over the same receiver:
		// Dart rejects a second extension of the same name in a library,
		// so same-receiver functions share one declaration (spec 10).
		// The receiver order is the first-encounter order, keeping the
		// output independent of map iteration order.
		final extractedParts: Array<String> = [];
		final extensionOrder: Array<String> = [];
		final extensionGroups = new Map<String, Array<ClassFuncData>>();
		for(f in extractedFuncs) {
			if(StaticFunctionMarkers.isTopLevel(f.field)) {
				extractedParts.push(topLevelFuncDecl(module, cls, f).join("\n"));
				continue;
			}
			final receiverType = types.of(f.args[0].type);
			if(!extensionGroups.exists(receiverType)) {
				extensionGroups.set(receiverType, []);
				extensionOrder.push(receiverType);
			}
			extensionGroups.get(receiverType).push(f);
		}
		for(receiverType in extensionOrder) {
			extractedParts.push(extensionDeclGroup(cls, receiverType, extensionGroups.get(receiverType)).join("\n"));
		}
		if(varFields.length == 0 && ordinaryFuncs.length == 0) {
			return extractedParts.join("\n\n");
		}
		final lines: Array<String> = [];

		// A statics-only business class lowers to top-level functions
		// because Dart keeps them library-scoped; an instance class
		// lowers to a final class (the samples carry no subclassing
		// outside haxe.Exception). Resident modules always keep the
		// class: the runtime library merges several modules whose
		// top-level function names would collide.
		if(flattenStatics(cls) && isStaticsOnly(varFields, ordinaryFuncs)) {
			// The data tables of a statics-only class become top-level
			// constants of its library (a top-level variable needs no
			// static keyword).
			for(v in varFields) {
				final decl = varDeclTopLevel(cls, module, v);
				if(decl.length == 0) {
					continue;
				}
				if(lines.length > 0) {
					lines.push("");
				}
				for(l in decl) {
					lines.push(l);
				}
			}
			for(f in ordinaryFuncs) {
				if(lines.length > 0) {
					lines.push("");
				}
				for(l in funcDecl(module, cls, f, true)) {
					lines.push(l);
				}
			}
			final classPart = lines.join("\n");
			return extractedParts.length > 0 ? extractedParts.join("\n\n") + "\n\n" + classPart : classPart;
		}

		final extendsClause = isException(cls) ? " extends " + runtimeBoringException() : "";
		final implementsClauses: Array<String> = [];
		for(i in cls.interfaces) {
			final iface = i.t.get();
			final prefix = imports.value(iface.module, iface.name);
			implementsClauses.push(prefix.length > 0 ? prefix + "." + iface.name : iface.name);
		}
		final implementsClause = implementsClauses.length > 0 ? " implements " + implementsClauses.join(", ") : "";
		lines.push("final class " + cls.name + classParamsOf(cls) + extendsClause + implementsClause + " {");

		// One blank line between members; none inside a member's body.
		// A coalescing constructor default assigns the field in the
		// body, which Dart accepts only under a late declaration.
		final lateFields = expr.coalescedBodyFields(cls, ordinaryFuncs);
		for(v in varFields) {
			final decl = varDecl(cls, module, v, lateFields);
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
		for(f in ordinaryFuncs) {
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
			for(l in funcDecl(module, cls, f, false)) {
				lines.push(l);
			}
		}

		lines.push("}");
		final classPart = lines.join("\n");
		return extractedParts.length > 0 ? extractedParts.join("\n\n") + "\n\n" + classPart : classPart;
	}

	/** Emits a marked abstract as a Dart extension type. */
	public function valueTypeDecl(cls: ClassType, info: ValueTypeInfo, varFields: Array<ClassVarData>, funcFields: Array<ClassFuncData>): String {
		final abs = info.abstractType;
		final ctor = ValueTypeSupport.constructorField(abs);
		final first = ctor == null ? null : ValueTypeSupport.firstArgument(ctor);
		if(first == null) Context.error("value type constructor must take its representation", cls.pos);
		final fieldName = first.name;
		final lines: Array<String> = ["extension type " + info.name + "(" + types.of(info.representation) + " " + fieldName + ") {"];
		for(f in funcFields) {
			if(f.field.name == "_new" || f.field.name == "toString" || (ValueTypeSupport.isInlineHelper(f.field) && ValueTypeSupport.operatorOf(abs, f.field) == null)) continue;
			final op = ValueTypeSupport.operatorOf(abs, f.field);
			final isOperator = op != null;
			final receiver = ValueTypeSupport.hasReceiver(f.field);
			final start = isOperator ? (switch(op) { case Binary(_): 1; case Unary(_): f.args.length; }) : (receiver ? 1 : 0);
			final ret = types.of(f.ret);
			final signature = if(isOperator) {
				switch(op) {
					case Binary(_): ret + " operator " + dartOperatorName(op) + "(" + info.name + " other)";
					case Unary(_): ret + " operator " + dartOperatorName(op) + "()";
				}
			} else {
				final args = [for(i in start...f.args.length) {
					final a = f.args[i];
					types.of(a.type) + " " + a.name;
				}].join(", ");
				ret + " " + f.field.name + "(" + args + ")";
			};
			lines.push("");
			lines.push("  " + signature + " {");
			for(line in expr.valueTypeFunctionBody(cls, f, fieldName)) lines.push(line);
			lines.push("  }");
		}
		if(ValueTypeSupport.memberField(abs, "toString") != null) {
			final f = findFunc(funcFields, "toString");
			lines.push("");
			// Dart extension types cannot redeclare Object.toString. The
			// source member is routed to this equivalent value method at
			// call sites while Object.toString remains available to Dart.
			lines.push("  String toStringValue() {");
			for(line in expr.valueTypeFunctionBody(cls, f, fieldName)) lines.push(line);
			lines.push("  }");
		}
		for(v in varFields) {
			if(!v.isStatic) continue;
			final initializer = v.field.expr();
			if(initializer == null) Context.error("value type static field must have an initializer", v.field.pos);
			lines.push("");
			lines.push("  static final " + info.name + " " + v.field.name + " = " + expr.rawExpression(initializer) + ";");
		}
		lines.push("}");
		final result = lines.copy();
		if(ctor != null && ValueTypeSupport.constructorThrows(abs)) {
			result.push("");
			result.push(info.name + " " + ValueTypeSupport.constructorName(abs) + "(" + types.of(info.representation) + " " + fieldName + ") {");
			for(line in expr.valueTypeConstructorBody(cls, findFunc(funcFields, "_new"))) result.push(line);
			result.push("  return " + info.name + "(" + fieldName + ");");
			result.push("}");
		}
		return result.join("\n");
	}

	function findFunc(funcFields: Array<ClassFuncData>, name: String): ClassFuncData {
		for(f in funcFields) if(f.field.name == name) return f;
		Context.error("value type member is missing: " + name, Context.currentPos());
		return null;
	}

	function dartOperatorName(op: ValueTypeOperator): String {
		return switch(op) {
			case Binary(binary): switch(binary) {
				case OpAdd: "+";
				case OpSub: "-";
				case OpMult: "*";
				case OpDiv: "/";
				case OpMod: "%";
				case OpEq: "==";
				case OpNotEq: "!=";
				case OpLt: "<";
				case OpLte: "<=";
				case OpGt: ">";
				case OpGte: ">=";
				case _: "+";
			};
			case Unary(unary): switch(unary) {
				case OpNeg: "-";
				case _: "+";
			};
		};
	}

	/** Whether this module's statics lower as top-level functions of their own library. */
	static function flattenStatics(cls: ClassType): Bool {
		return !RuntimeResidents.isResident(cls.module);
	}

	static function isStaticsOnly(varFields: Array<ClassVarData>, funcFields: Array<ClassFuncData>): Bool {
		for(v in varFields) {
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

	/** The exception base as this library references it. */
	function runtimeBoringException(): String {
		final prefix = imports.runtimePrefix();
		return prefix.length > 0 ? prefix + ".BoringException" : "BoringException";
	}

	function classParamsOf(cls: ClassType): String {
		return cls.params.length > 0 ? "<" + [for(p in cls.params) p.name].join(", ") + ">" : "";
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

	function varDecl(cls: ClassType, module: String, v: ClassVarData, lateFields: Map<String, Bool>): Array<String> {
		final field = v.field;
		if(v.isStatic && DataTableHelper.isDataTableField(field)) {
			final elems = DataTableHelper.getDataTableElements(field.expr());
			if(elems != null) {
				return ["  static final List<int> " + claimTopLevel(field.name, field.pos) + " = [" + renderDataTableElements(elems) + "];"];
			}
		}
		if(v.isStatic && isFunctionType(field.type)) {
			final initializer = field.expr();
			if(initializer == null) {
				Context.error("static function fields require initializers", field.pos);
				return [];
			}
			final name = field.isPublic ? field.name : "_" + field.name;
			return ["  static final " + types.of(field.type) + " " + name + " = " + expr.rawExpression(initializer) + ";"];
		}
		if(v.isStatic) {
			final init = StaticFieldHelper.validatedInitializer(field, cls);
			final name = field.isPublic ? field.name : "_" + field.name;
			final kw = field.isFinal ? "final " : "";
			final type = StaticFieldHelper.isSelfConstruction(field, cls, init) ? "" : types.of(field.type) + " ";
			return ["  static " + kw + type + name + " = " + expr.rawExpression(init) + ";"];
		}
		if(field.meta.has(":value")) {
			Context.error("instance field default has no lowering; assign it in the constructor", field.pos);
		}
		// A `var x(get, never)` field renders no storage; the getter
		// beside the accessor function is the lowering (feature spec 27).
		if(isGetterOnlyProperty(field)) {
			return [];
		}
		// A private field renders under its `_`-prefixed Dart name
		// (feature spec 27). A final Haxe field pins the reference, not
		// the contents: an array field still grows in place (the sorted
		// builders), and a Dart final pins exactly the reference, so the
		// keywords agree. A mutable field names its type; Dart spells
		// mutable without a keyword.
		final name = field.isPublic ? field.name : "_" + field.name;
		// A field the constructor initializes through a coalescing
		// body site declares late (late final on final fields);
		// definite-assignment analysis accepts no other body shape
		// (feature spec 22).
		final late = lateFields.exists(field.name) ? "late " : "";
		if(field.isFinal) {
			return ["  " + late + "final " + types.of(field.type) + " " + name + ";"];
		}
		return ["  " + late + types.of(field.type) + " " + name + ";"];
	}

	static function isFunctionType(t: Null<Type>): Bool {
		if(t == null) {
			return false;
		}
		return switch(Context.follow(t)) {
			case TFun(_, _): true;
			case _: false;
		};
	}

	/** A `var x(get, never)` field renders no storage on this target (feature spec 27). */
	static function isGetterOnlyProperty(field: ClassField): Bool {
		switch(field.kind) {
			case FVar(read, write):
				return read.match(AccCall) && write.match(AccNever);
			case _:
				return false;
		}
	}

	/**
		A getter-only property renders as a Dart getter reading the
		standard accessor (feature spec 27). The typer lowers property
		reads to `get_x()` calls, so the getter serves consuming Dart
		code; the accessor's own privacy gives its Dart name.
	**/
	function propertyDecl(cls: ClassType, field: ClassField): Array<String> {
		final accessor = "get_" + field.name;
		var getter = accessor;
		for(f in cls.fields.get()) {
			if(f.name == accessor) {
				getter = f.isPublic ? f.name : "_" + f.name;
				break;
			}
		}
		final name = field.isPublic ? field.name : "_" + field.name;
		return ["  " + types.of(field.type) + " get " + name + " => " + getter + "();"];
	}

	/**
		The static data table of a flattened statics-only class: a
		top-level constant of the library, otherwise the member shape of
		`varDecl`.
	**/
	function varDeclTopLevel(cls: ClassType, module: String, v: ClassVarData): Array<String> {
		final field = v.field;
		if(v.isStatic && DataTableHelper.isDataTableField(field)) {
			final elems = DataTableHelper.getDataTableElements(field.expr());
			if(elems != null) {
				return ["final List<int> " + claimTopLevel(field.name, field.pos) + " = [" + renderDataTableElements(elems) + "];"];
			}
		}
		if(v.isStatic && isFunctionType(field.type)) {
			final initializer = field.expr();
			if(initializer == null) {
				Context.error("static function fields require initializers", field.pos);
				return [];
			}
			final name = claimTopLevel(field.isPublic ? field.name : "_" + field.name, field.pos);
			return ["final " + types.of(field.type) + " " + name + " = " + expr.rawExpression(initializer) + ";"];
		}
		if(v.isStatic) {
			final init = StaticFieldHelper.validatedInitializer(field, cls);
			final name = field.isPublic ? field.name : "_" + field.name;
			final kw = field.isFinal ? "final " : "";
			final type = StaticFieldHelper.isSelfConstruction(field, cls, init) ? "" : types.of(field.type) + " ";
			return [kw + type + name + " = " + expr.rawExpression(init) + ";"];
		}
		Context.error("a statics-only class carries data tables and inline constants only", field.pos);
		return [];
	}

	function renderDataTableElements(elems: Array<Int>): String {
		final formatted = [for(x in elems) (x >= 0 && x <= 9) ? Std.string(x) : "0x" + StringTools.hex(x).toLowerCase()];
		final chunks: Array<String> = [];
		var i = 0;
		while(i < formatted.length) {
			final end = Std.int(Math.min(i + 8, formatted.length));
			chunks.push("\n    " + formatted.slice(i, end).join(", "));
			i = end;
		}
		return chunks.join(",") + "\n  ";
	}

	/**
		One @:test function (features/19): a top-level function of the
		test module's library. The runner entry that calls it lands in
		main.dart.
	**/
	public function testFuncDecl(cls: ClassType, f: ClassFuncData): Array<String> {
		for(a in f.args) {
			expr.reserveName(a.name);
		}
		final head = "void " + claimTopLevel(f.field.name, f.field.pos) + "() {";
		return [head].concat(expr.functionBody(cls, f, 1)).concat(["}"]);
	}

	/**
		One member declaration. A top-level function renders unindented
		without the static keyword (the flattened statics-only form and
		the @:test functions); a class member renders indented with
		`static` on statics.
	**/
	function funcDecl(module: String, cls: ClassType, f: ClassFuncData, topLevel: Bool): Array<String> {
		// Haxe types constructors as FMethod(MethNormal) with field name
		// "new"; the name is the constructor marker. Dart initializes
		// fields through the parameter list and the initializer list,
		// and the superinitializer renders last.
		if(f.field.name == "new") {
			for(a in f.args) {
				expr.reserveName(a.name);
			}
			final parts = expr.constructorParts(cls, f);
			final params = constructorParamList(cls, f, parts.formalFields);
			final initializers: Array<String> = parts.fieldInits.copy();
			if(parts.superCall != null) {
				initializers.push(parts.superCall);
			}
			final head = "  " + cls.name + "(" + params + ")" + (initializers.length > 0 ? " : " + initializers.join(", ") : "") + " {";
			return [head].concat(parts.body).concat(["  }"]);
		}
		for(a in f.args) {
			expr.reserveName(a.name);
		}
		final methodParams = collectMethodTypeParams(cls, f);
		final genericStr = methodParams.length > 0 ? "<" + methodParams.join(", ") + ">" : "";
		// A private function renders under its `_`-prefixed Dart name
		// (feature spec 27), member and flattened top-level alike.
		final name = f.field.isPublic ? f.field.name : "_" + f.field.name;
		if(topLevel) {
			claimTopLevel(name, f.field.pos);
			final head = '${types.of(f.ret)} $name$genericStr${paramList(cls, f)} {';
			return [head].concat(expr.functionBody(cls, f, 1)).concat(["}"]);
		}
		final stat = f.isStatic ? "static " : "";
		final head = '  ${stat}${types.of(f.ret)} $name$genericStr${paramList(cls, f)} {';
		return [head].concat(expr.functionBody(cls, f, 2)).concat(["  }"]);
	}

	function topLevelFuncDecl(module: String, cls: ClassType, f: ClassFuncData): Array<String> {
		return funcDecl(module, cls, f, true);
	}

	/**
		One extension declaration holding every marked extension function
		over the same receiver type. Dart rejects a second extension of
		the same name inside one library, so the grouping is mandatory
		(spec 10).
	**/
	function extensionDeclGroup(cls: ClassType, receiverType: String, funcs: Array<ClassFuncData>): Array<String> {
		final lines: Array<String> = ["extension " + dartExtensionName(receiverType) + " on " + receiverType + " {"];
		for(f in funcs) {
			for(a in f.args) {
				expr.reserveName(a.name);
			}
			final methodParams = collectMethodTypeParams(cls, f);
			final genericStr = methodParams.length > 0 ? "<" + methodParams.join(", ") + ">" : "";
			final name = f.field.isPublic ? f.field.name : "_" + f.field.name;
			final head = '  ${types.of(f.ret)} $name$genericStr${paramList(cls, f, 1)} {';
			if(f.args[0].tvar != null) {
				expr.bindLocalName(f.args[0].tvar, "this");
			}
			lines.push(head);
			for(l in expr.functionBody(cls, f, 2)) {
				lines.push(l);
			}
			lines.push("  }");
		}
		lines.push("}");
		return lines;
	}

	/** The signature of one method without body or leading indent. */
	function methodSignature(cls: ClassType, f: ClassFuncData): String {
		final ret = types.of(f.ret);
		return '$ret ${f.field.name}${paramList(cls, f)}';
	}

	/**
		The Dart extension name for one receiver type. Unnamed extensions
		resolve only inside their declaring library, so cross-library
		consumers need a named extension (spec 10). Characters outside
		identifiers drop from the rendered receiver type.
	**/
	function dartExtensionName(receiverType: String): String {
		final safe = new EReg("[^A-Za-z0-9_]", "g").replace(receiverType, "");
		return safe + "Extension";
	}

	/**
		Parameter rendering. Dart's optional positional group is reserved for
		coalescing defaults; constant defaults have already been materialized
		at every call site and remain required parameters.
	**/
	function paramList(cls: ClassType, f: ClassFuncData, start: Int = 0): String {
		final required: Array<String> = [];
		final optional: Array<String> = [];
		var optionalStarted = false;
		for(i in start...f.args.length) {
			final a = f.args[i];
			final part = types.of(a.type) + " " + a.name;
			if(DefaultArgExpander.coalescingDefaultAt(cls, f.field.name, a.index) != null) {
				optionalStarted = true;
			}
			if(optionalStarted) {
				optional.push(part);
			} else {
				required.push(part);
			}
		}
		final groups = required.copy();
		if(optional.length > 0) {
			groups.push("[" + optional.join(", ") + "]");
		}
		return "(" + groups.join(", ") + ")";
	}

	/** Constructor parameters use the same optional positional group, while
		retaining Dart's initializing-formal spelling for direct assignments. */
	function constructorParamList(cls: ClassType, f: ClassFuncData, formalFields: Map<String, String>): String {
		final required: Array<String> = [];
		final optional: Array<String> = [];
		var optionalStarted = false;
		for(a in f.args) {
			final part = formalFields.exists(a.name) ? "this." + formalFields.get(a.name) : types.of(a.type) + " " + a.name;
			if(DefaultArgExpander.coalescingDefaultAt(cls, f.field.name, a.index) != null) {
				optionalStarted = true;
			}
			if(optionalStarted) {
				optional.push(part);
			} else {
				required.push(part);
			}
		}
		final groups = required.copy();
		if(optional.length > 0) {
			groups.push("[" + optional.join(", ") + "]");
		}
		return groups.join(", ");
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
				final cl = c.get();
				if(switch(cl.kind) {
					// Haxe 4.3 carries the parameter's constraints on
					// the kind constructor.
					case KTypeParameter(_): true;
					case _: false;
				}) {
					if(skip.indexOf(cl.name) < 0 && found.indexOf(cl.name) < 0) {
						found.push(cl.name);
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

	// ------------------------------------------------------------------
	// Variant enums (features/01)
	// ------------------------------------------------------------------

	/**
		A variant enum lowers to a sealed class with one final subclass
		per construct (docs/specs/stdlib/06-std-modules.md). The subclasses carry
		their payloads as public final fields, and the generated equality
		and hashCode back the construct comparisons the samples run
		(`mode == Mode.Write`) and the pattern switches exhaust over the
		sealed hierarchy with no default arm.
	**/
	public function enumDecl(en: EnumType, options: Array<EnumOptionData>): String {
		final sorted = options.copy();
		sorted.sort((a, b) -> Reflect.compare(a.field.index, b.field.index));
		var valueEnum = true;
		for(o in sorted) if(o.args.length > 0) valueEnum = false;
		if(valueEnum) {
			final lines = ['enum ${claimTopLevel(en.name, en.pos)} {'];
			for(i in 0...sorted.length) {
				final o = sorted[i];
				lines.push('  ${lowerFirst(o.name)}("${o.name}")' + (i == sorted.length - 1 ? ";" : ","));
			}
			lines.push("");
			lines.push("  final String label;");
			lines.push('  const ${en.name}(this.label);');
			lines.push("}");
			final use = EnumQueryExpander.usage(en);
			if(use != null && use.lookup) {
				final fn = EnumQueryExpander.lowerFirst(en.name) + "OfName";
				lines.push(""); lines.push('${en.name}? $fn(String name) {');
				for(o in sorted) lines.push('  if (name == "${o.name}") return ${en.name}.${lowerFirst(o.name)};');
				lines.push("  return null;"); lines.push("}");
			}
			return lines.join("\n");
		}
		final lines: Array<String> = ["sealed class " + claimTopLevel(en.name, en.pos) + " {"];
		lines.push("}");
		for(o in sorted) {
			lines.push("");
			for(l in constructDecl(en, o)) {
				lines.push(l);
			}
		}
		return lines.join("\n");
	}

	function constructDecl(en: EnumType, o: EnumOptionData): Array<String> {
		final clsName = constructClassName(en.name, o.name);
		final lines: Array<String> = ["final class " + claimTopLevel(clsName, o.field.pos) + " extends " + en.name + " {"];
		final payloadArgs = o.args;
		if(payloadArgs.length > 0) {
			for(arg in payloadArgs) {
				lines.push("  final " + types.of(arg.type) + " " + arg.name + ";");
			}
			lines.push("");
			lines.push("  " + clsName + "(" + [for(arg in payloadArgs) "this." + arg.name].join(", ") + ");");
		}
		final comparisons: Array<String> = [];
		for(arg in payloadArgs) {
			comparisons.push("other." + arg.name + " == " + arg.name);
		}
		lines.push("");
		lines.push("  @override");
		lines.push("  bool operator ==(Object other) {");
		lines.push("    if (identical(this, other)) {");
		lines.push("      return true;");
		lines.push("    }");
		lines.push("    return other is " + clsName + (comparisons.length > 0 ? " && " + comparisons.join(" && ") : "") + ";");
		lines.push("  }");
		lines.push("");
		lines.push("  @override");
		lines.push("  int get hashCode {");
		if(payloadArgs.length == 0) {
			lines.push("    return 17;");
		} else {
			lines.push("    var hash = 17;");
			for(arg in payloadArgs) {
				lines.push("    hash = 37 * hash + " + arg.name + ".hashCode;");
			}
			lines.push("    return hash;");
		}
		lines.push("  }");
		lines.push("}");
		return lines;
	}

	/** The generated subclass name of one variant construct. */
	public static function constructClassName(enumName: String, constructName: String): String {
		return enumName + upperFirst(constructName);
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
				var hasListField = false;
				for(field in fields) {
					if(isListType(field.type)) {
						hasListField = true;
						break;
					}
				}
				final lines: Array<String> = ["class " + claimTopLevel(def.name, def.pos) + " {"];
				for(field in fields) {
					lines.push("  final " + types.of(field.type) + " " + field.name + ";");
				}
				lines.push("");
				lines.push("  " + def.name + "(" + [for(f in fields) "this." + f.name].join(", ") + ");");
				lines.push("");
				lines.push("  @override");
				lines.push("  bool operator ==(Object other) {");
				lines.push("    if (identical(this, other)) {");
				lines.push("      return true;");
				lines.push("    }");
				final comparisons: Array<String> = [];
				for(f in fields) {
					if(isListType(f.type)) {
						seqEqualsNeeded = true;
						comparisons.push("_seqEquals(" + f.name + ", other." + f.name + ")");
					} else {
						comparisons.push("other." + f.name + " == " + f.name);
					}
				}
				lines.push("    return other is " + def.name + (comparisons.length > 0 ? " && " + comparisons.join(" && ") : "") + ";");
				lines.push("  }");
				lines.push("");
				lines.push("  @override");
				lines.push("  int get hashCode {");
				lines.push("    var hash = 17;");
				for(f in fields) {
					lines.push("    hash = 37 * hash + " + (isListType(f.type) ? "Object.hashAll(" + f.name + ")" : f.name + ".hashCode") + ";");
				}
				lines.push("    return hash;");
				lines.push("  }");
				lines.push("}");
				if(hasListField) {
					lines.push("");
					lines.push(seqEqualsSource());
				}
				if(isStructKeyCandidate(fields)) {
					return lines.join("\n") + "\n\n" + comparatorDecl(def, fields).join("\n");
				}
				return lines.join("\n");
			case _:
				Context.error("typedef alias has no lowering; name the structure instead", def.pos);
				return null;
		}
	}

	static function isListType(t: Type): Bool {
		return switch(t) {
			case TInst(c, _):
				final cl = c.get();
				(cl.pack.length == 0 && cl.name == "Array") || (cl.pack.join(".") == "std" && cl.name == "ReadOnlyArray");
			case TLazy(f): isListType(f());
			case _: false;
		};
	}

	/** The private list equality of one library; element equality is the elements' own operator. */
	static function seqEqualsSource(): String {
		return [
			"bool _seqEquals(List<dynamic> a, List<dynamic> b) {",
			"  if (a.length != b.length) {",
			"    return false;",
			"  }",
			"  for (var i = 0; i < a.length; i++) {",
			"    final x = a[i];",
			"    final y = b[i];",
			"    if (x is List && y is List) {",
			"      if (!_seqEquals(x, y)) {",
			"        return false;",
			"      }",
			"    } else if (x != y) {",
			"      return false;",
			"    }",
			"  }",
			"  return true;",
			"}"
		].join("\n");
	}

	/**
		The per-type key comparator stdlib/07 binds into sorted builders
		with structure keys. Integer fields subtract; Bool fields branch;
		String fields compare through native compareTo, which uses
		UTF-16 code-unit order on this target; nested structures
		delegate to their comparator.
	**/
	function comparatorDecl(def: DefType, fields: Array<ClassField>): Array<String> {
		final fnName = claimTopLevel("compare" + def.name, def.pos);
		final lines: Array<String> = [
			"int " + fnName + "(" + def.name + " a, " + def.name + " b) {"
		];
		for(f in fields) {
			switch(Context.follow(f.type)) {
				case TAbstract(a, _) if(a.get().name == "Int"):
					lines.push("  if (a." + f.name + " != b." + f.name + ") {");
					lines.push("    return a." + f.name + " - b." + f.name + ";");
					lines.push("  }");
				case TAbstract(a, _) if(a.get().name == "Bool"):
					lines.push("  if (a." + f.name + " != b." + f.name + ") {");
					lines.push("    return a." + f.name + " ? 1 : -1;");
					lines.push("  }");
				case TInst(c, _) if(c.get().name == "String"):
					lines.push("  if (a." + f.name + " != b." + f.name + ") {");
					lines.push("    return a." + f.name + ".compareTo(b." + f.name + ");");
					lines.push("  }");
				case _:
					switch(f.type) {
						case TType(innerDef, _):
							final inner = innerDef.get();
							final orderName = "order" + upperFirst(f.name);
							lines.push("  final " + orderName + " = compare" + inner.name + "(a." + f.name + ", b." + f.name + ");");
							lines.push("  if (" + orderName + " != 0) {");
							lines.push("    return " + orderName + ";");
							lines.push("  }");
						case _:
					}
			}
		}
		lines.push("  return 0;");
		lines.push("}");
		return lines;
	}

	static function upperFirst(s: String): String {
		return s.charAt(0).toUpperCase() + s.substr(1);
	}

	/** The Dart file stem of a module: `pack.ModuleName` maps to `pack/module_name.dart`. */
	public static function snakeCase(s: String): String {
		final b = new StringBuf();
		for(i in 0...s.length) {
			final c = s.charCodeAt(i);
			if(c >= "A".code && c <= "Z".code) {
				if(i > 0) {
					b.add("_");
				}
				b.addChar(c + 32);
			} else {
				b.addChar(c);
			}
		}
		return b.toString();
	}

	static function isStructKeyCandidate(fields: Array<ClassField>): Bool {
		for(f in fields) {
			if(!isFieldKeyCandidate(f.type)) return false;
		}
		return true;
	}

	static function isFieldKeyCandidate(t: Type): Bool {
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

	// ------------------------------------------------------------------
	// Internals
	// ------------------------------------------------------------------

	/**
		Claims one top-level name for this library. The flattened
		functions, the generated record and construct classes, and the
		comparators share one namespace per file; a collision is a naming
		bug the compiler reports instead of emitting broken Dart.
	**/
	function claimTopLevel(name: String, pos: haxe.macro.Expr.Position): String {
		if(topLevelNames.exists(name)) {
			Context.error("top-level name " + name + " is claimed twice in " + imports.selfModule, pos);
		}
		topLevelNames.set(name, true);
		return name;
	}
}
#end
