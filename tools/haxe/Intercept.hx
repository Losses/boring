/**
 * Generation interception for the Haxe style standard,
 * docs/specs/style/01-haxe-style-standard.md. Registered from every compile
 * that feeds the pipeline: `--macro Intercept.run(['haxe/src', 'tests/haxe'])`.
 *
 * Two passes, one per AST form the rules need:
 *
 *   1. A @:build pass over the untyped field expressions, injected into
 *      every class through Compiler.addGlobalMetadata and guarded by source
 *      path. The untyped tree is the only layer where the source constructs
 *      survive: the typer rewrites `for (item in array)` into a counter
 *      while loop, expands `array.map(fn)` into an inlined loop that calls
 *      the function value, and inlines `Reflect.hasField` into a prototype
 *      call before any after-typing callback can observe them.
 *   2. An after-typing pass over the typed expressions of every module
 *      under the guarded roots, for the rules that need types.
 *
 * Neither pass repairs or falls back; a rejection means the source changes
 * or the specification changes.
 *
 * The rejection table is the contract; every row here has a row there:
 *   V01 IteratorLoop       for subject that is not an integer range     [pass 1]
 *   V02 FunctionalIteration Lambda, array method callbacks, comparator sort [pass 1]
 *   V03 Reflection         Reflect and Type module calls                [pass 1]
 *   V04 UntypedThrow       throw of a non-enum-carrying exception value  [pass 2]
 *   V05 DynamicValue       untyped block; expression typed Dynamic, untargeted cast [1+2]
 *   V06 StringKeyedAccess  bracket access with a String key on a structure [pass 2]
 *   V07 ShapeMutation      assignment to a final field                   [compiler]
 *   V08 LoopBodyClosure    function value inside a loop body             [pass 2]
 *   V11 Int64Misuse        haxe.Int64 outside the permitted modules      [pass 2]
 *   V12 DataInheritance    guarded class extends outside the exception chain [pass 2]
 *   V13 HashMapCollection  haxe.ds.Map and its implementations           [pass 2]
 *   V14 DynamicCatch       catch variable typed Dynamic                  [pass 2]
 *   V15 EnumDefaultArm     switch over an enum with a default arm        [pass 2]
 * V09 and V10 are schema-level checks on the FormatDef, not AST checks.
 */
// Imports spell out every referenced type: module wildcards over
// haxe.macro.Type resolve as constructor imports here, and the compiler
// reports only the first missing type, which hides the rest of the damage.
import haxe.macro.Compiler;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Expr.Binop;
import haxe.macro.Expr.Constant;
import haxe.macro.Expr.FieldType;
import haxe.macro.Expr.Position;
import haxe.macro.ExprTools;
import haxe.macro.Type;
import haxe.macro.Type.ClassField;
import haxe.macro.Type.ClassType;
import haxe.macro.Type.FieldAccess;
import haxe.macro.Type.TypedExpr;
import haxe.macro.Type.TypedExprDef;

class Intercept {
	/** Field names whose call form is banned on any receiver (V02). */
	static final FUNCTIONAL_METHODS:Array<String> = [
		"map", "filter", "fold", "reduce", "forEach", "flatMap", "find", "some",
		"every", "sortedBy",
	];

	/** Map modules with no translation (V13). */
	static final MAP_MODULES:Array<String> = [
		"haxe.ds.Map", "haxe.ds.StringMap", "haxe.ds.IntMap", "haxe.ds.ObjectMap",
		"haxe.ds.HashMap",
	];

	/** Root-level modules whose static calls are reflection (V03). */
	static final REFLECTION_ROOTS:Array<String> = ["Reflect", "Type"];

	/** Roots guarded by this run; only expressions under them are checked. */
	static final roots:Array<String> = [];

	/**
	 * Files permitted to reference haxe.Int64 (V11): the FPHelper float
	 * conversion paths that docs/specs/stdlib/05-haxe-int64.md sanctions.
	 */
	static final INT64_MODULE_ALLOWLIST:Array<String> = [
		"haxe/src/boring/BinaryReader.hx",
		"haxe/src/boring/BinaryWriter.hx",
	];

	public static function run(rootPrefixes:Array<String>):Void {
		for (index in 0...rootPrefixes.length) {
			roots.push(rootPrefixes[index]);
		}
		Compiler.addGlobalMetadata("", "@:build(Intercept.buildFields())", true, true);
		Context.onAfterTyping(walkModules);
	}

	/**
	 * Pass 1. Runs as a @:build macro on every class; the guard skips
	 * everything outside the source roots before any field is walked.
	 */
	macro public static function buildFields():Array<Field> {
		final fields = Context.getBuildFields();
		final localClass = Context.getLocalClass();
		if (localClass == null) {
			return fields;
		}
		final classType = localClass.get();
		if (!isGuarded(classType.pos)) {
			return fields;
		}
		for (index in 0...fields.length) {
			final field = fields[index];
			switch (field.kind) {
				case FieldType.FVar(_, expression):
					if (expression != null) {
						walkSource(expression);
					}
				case FieldType.FProp(_, _, _, expression):
					if (expression != null) {
						walkSource(expression);
					}
				case FieldType.FFun(fun):
					if (fun.expr != null) {
						walkSource(fun.expr);
					}
			}
		}
		return fields;
	}

	static function walkSource(e:Expr):Void {
		switch (e.expr) {
			case ExprDef.EFor(iterator, _):
				// The parser wraps the whole head as EBinop(OpIn, variable,
				// subject); the range check looks at the subject operand.
				final subject = switch (iterator.expr) {
					case ExprDef.EBinop(Binop.OpIn, _, range): range;
					default: iterator;
				};
				switch (subject.expr) {
					case ExprDef.EBinop(Binop.OpInterval, _, _):
					default:
						violation("V01", "IteratorLoop",
							"for subject is not an integer range; arrays iterate as for (i in 0...array.length)",
							iterator.pos);
				}
			case ExprDef.ECall(callee, args):
				checkSourceCall(callee, args);
			case ExprDef.EUntyped(_):
				violation("V05", "DynamicValue",
					"untyped block; the translatable subset declares types", e.pos);
			case ExprDef.ECast(_, null):
				violation("V05", "DynamicValue",
					"cast without a target type; the translatable subset declares types", e.pos);
			default:
		}
		ExprTools.iter(e, walkSource);
	}

	static function checkSourceCall(callee:Expr, args:Array<Expr>):Void {
		switch (callee.expr) {
			case ExprDef.EField(receiver, name):
				if (name == "sort") {
					if (args.length > 0) {
						violation("V02", "FunctionalIteration",
							"comparator sort rewrites to a plain loop before translation; the exit is the sort runtime of features/17",
							callee.pos);
					}
					return;
				}
				for (index in 0...FUNCTIONAL_METHODS.length) {
					if (name == FUNCTIONAL_METHODS[index]) {
						violation("V02", "FunctionalIteration",
							'.$name rewrites to a plain loop before translation', callee.pos);
					}
				}
				switch (receiver.expr) {
					case ExprDef.EConst(Constant.CIdent(root)):
						for (index in 0...REFLECTION_ROOTS.length) {
							if (root == REFLECTION_ROOTS[index]) {
								violation("V03", "Reflection",
									'$root.$name has no translation with identical behavior', callee.pos);
							}
						}
					default:
				}
			default:
		}
	}

	/**
	 * Pass 2. After the compiler types all modules, walks every typed
	 * expression of every guarded class.
	 */
	static function walkModules(modules:Array<haxe.macro.Type.ModuleType>):Void {
		for (index in 0...modules.length) {
			switch (modules[index]) {
				case haxe.macro.Type.ModuleType.TClassDecl(classRef):
					final classType = classRef.get();
					if (!isGuarded(classType.pos)) {
						continue;
					}
					checkDataInheritance(classType);
					walkClassFields(classType.fields.get());
					walkClassFields(classType.statics.get());
				default:
			}
		}
	}

	static function walkClassFields(fields:Array<ClassField>):Void {
		for (index in 0...fields.length) {
			final field = fields[index];
			if (field.expr == null) {
				continue;
			}
			final body = field.expr();
			if (body == null) {
				continue;
			}
			if (!isGuarded(body.pos)) {
				continue;
			}
			walk(body, false);
		}
	}

	static function isGuarded(position:Position):Bool {
		final infos = Context.getPosInfos(position);
		for (index in 0...roots.length) {
			if (StringTools.startsWith(infos.file, roots[index])) {
				return true;
			}
		}
		return false;
	}

	static function walk(e:TypedExpr, inLoop:Bool):Void {
		if (e == null) {
			return;
		}
		// Specific arms run first: a node that violates a named rule reports
		// that rule, so the generic type checks below never pre-empt a more
		// precise diagnosis. The dynamic check skips control completion
		// nodes, which the compiler types Dynamic by construction (throw,
		// return, break, continue, and blocks ending in them); their
		// children are still walked. Compiler-inserted coercion casts
		// (TCast without a module type) are skipped for the same reason:
		// the source-level cast check runs in pass 1 on the untyped tree.
		switch (e.expr) {
			case TypedExprDef.TFor(_, subject, body):
				walk(subject, inLoop);
				walk(body, true);
			case TypedExprDef.TWhile(condition, body, _):
				walk(condition, inLoop);
				walk(body, true);
			case TypedExprDef.TFunction(func):
				if (inLoop) {
					violation("V08", "LoopBodyClosure", "function value inside a loop body", e.pos);
				}
				walk(func.expr, false);
			case TypedExprDef.TCall(callee, args):
				walk(callee, inLoop);
				walkAll(args, inLoop);
			case TypedExprDef.TArray(subject, index):
				checkStringKeyedAccess(subject, index);
				walk(subject, inLoop);
				walk(index, inLoop);
			case TypedExprDef.TBinop(Binop.OpAssign, target, value):
				checkFinalAssign(target);
				walk(target, inLoop);
				walk(value, inLoop);
			case TypedExprDef.TThrow(inner):
				checkThrow(inner);
				walk(inner, inLoop);
			case TypedExprDef.TTry(body, catches):
				walk(body, inLoop);
				for (index in 0...catches.length) {
					final catchVariable = catches[index].v;
					switch (catchVariable.t) {
						case Type.TDynamic(_):
							violation("V14", "DynamicCatch",
								"catch variable is typed Dynamic; catch clauses name the exception type",
								e.pos);
						default:
					}
					walk(catches[index].expr, inLoop);
				}
			case TypedExprDef.TSwitch(subject, cases, maybeDefault):
				checkEnumDefault(subject, maybeDefault);
				walk(subject, inLoop);
				for (index in 0...cases.length) {
					walkAll(cases[index].values, inLoop);
					walk(cases[index].expr, inLoop);
				}
				if (maybeDefault != null) {
					walk(maybeDefault, inLoop);
				}
			default:
				walkChildren(e, inLoop);
		}
		// js.Syntax code-feature calls are how extern inlines such as
		// String.fromCharCode expand on the js target; the call node is
		// typed Dynamic by that machinery, not by the source.
		final skipDynamicCheck = switch (e.expr) {
			case TypedExprDef.TThrow(_)
				| TypedExprDef.TReturn(_)
				| TypedExprDef.TBreak
				| TypedExprDef.TContinue
				| TypedExprDef.TBlock(_)
				| TypedExprDef.TCast(_, _):
				true;
			case TypedExprDef.TCall(callee, _):
				isSyntaxPlumbingCall(callee);
			default:
				false;
		};
		if (!skipDynamicCheck) {
			checkDynamic(e);
		}
		checkMapType(e);
		checkInt64(e);
	}

	static function walkChildren(e:TypedExpr, inLoop:Bool):Void {
		// The walker lives outside the guarded roots; the closure here is
		// tooling, so the loop-body closure rule does not bind it.
		haxe.macro.TypedExprTools.iter(e, (child:TypedExpr) -> {
			walk(child, inLoop);
		});
	}

	static function walkAll(expressions:Array<TypedExpr>, inLoop:Bool):Void {
		for (index in 0...expressions.length) {
			walk(expressions[index], inLoop);
		}
	}

	static function checkThrow(inner:TypedExpr):Void {
		switch (inner.t) {
			case Type.TInst(classRef, _):
				if (!isEnumCarryingException(classRef.get())) {
					violation("V04", "UntypedThrow",
						"throw constructs an enum-carrying haxe.Exception subclass",
						inner.pos);
				}
			default:
				violation("V04", "UntypedThrow",
					"throw constructs an enum-carrying haxe.Exception subclass",
					inner.pos);
		}
	}

	static function isEnumCarryingException(start:ClassType):Bool {
		var current:Null<ClassType> = start;
		while (current != null) {
			if (current.pack.join(".") == "haxe" && current.name == "Exception") {
				return false;
			}
			if (declaresEnumField(current)) {
				return true;
			}
			final parent = current.superClass;
			current = parent == null ? null : parent.t.get();
		}
		return false;
	}

	static function declaresEnumField(classType:ClassType):Bool {
		final fields = classType.fields.get();
		for (index in 0...fields.length) {
			switch (fields[index].type) {
				case Type.TEnum(_, _):
					return true;
				default:
			}
		}
		return false;
	}

	static function checkStringKeyedAccess(subject:TypedExpr, index:TypedExpr):Void {
		final indexIsString = switch (index.t) {
			case Type.TInst(classRef, _):
				classRef.get().module == "String";
			default:
				false;
		};
		if (!indexIsString) {
			return;
		}
		switch (subject.t) {
			case Type.TAnonymous(_):
				violation("V06", "StringKeyedAccess",
					"field access on a structure uses the dot form; brackets are for integer indices",
					index.pos);
			default:
		}
	}

	static function checkFinalAssign(target:TypedExpr):Void {
		switch (target.expr) {
			case TypedExprDef.TField(_, FieldAccess.FAnon(fieldRef))
				| TypedExprDef.TField(_, FieldAccess.FInstance(_, _, fieldRef)):
				if (fieldRef.get().isFinal) {
					violation("V07", "ShapeMutation",
						"assignment targets a final field", target.pos);
				}
			default:
		}
	}

	static function isSyntaxPlumbingCall(callee:TypedExpr):Bool {
		switch (callee.expr) {
			case TypedExprDef.TField(_, FieldAccess.FStatic(classRef, _)):
				return classRef.get().module == "js.Syntax";
			default:
				return false;
		}
	}

	static function checkDynamic(e:TypedExpr):Void {
		switch (e.t) {
			case Type.TDynamic(_):
				violation("V05", "DynamicValue",
					"expression is typed Dynamic; the translatable subset declares types",
					e.pos);
			default:
		}
	}

	static function checkMapType(e:TypedExpr):Void {
		switch (e.t) {
			case Type.TAbstract(abstractRef, _):
				if (moduleBanned(abstractRef.get().module)) {
					violation("V13", "HashMapCollection",
						"haxe.ds.Map and its implementations have no translation", e.pos);
				}
			case Type.TInst(classRef, _):
				if (moduleBanned(classRef.get().module)) {
					violation("V13", "HashMapCollection",
						"haxe.ds.Map and its implementations have no translation", e.pos);
				}
			default:
		}
	}

	static function moduleBanned(module:String):Bool {
		for (index in 0...MAP_MODULES.length) {
			if (module == MAP_MODULES[index]) {
				return true;
			}
		}
		return false;
	}

	static function checkDataInheritance(classType:ClassType):Void {
		final parent = classType.superClass;
		if (parent == null) {
			return;
		}
		var current:Null<ClassType> = parent.t.get();
		while (current != null) {
			if (current.pack.join(".") == "haxe" && current.name == "Exception") {
				return;
			}
			final next = current.superClass;
			current = next == null ? null : next.t.get();
		}
		violation("V12", "DataInheritance",
			"class extends outside the haxe.Exception chain that rule 4 sanctions",
			classType.pos);
	}

	static function checkEnumDefault(subject:TypedExpr, maybeDefault:Null<TypedExpr>):Void {
		if (maybeDefault == null) {
			return;
		}
		// The typer rewrites an enum switch into a switch over the variant
		// index, wrapping the subject in TEnumIndex; the wrapper is the
		// reliable marker that the source switched over an enum.
		final isEnumSwitch = switch (subject.expr) {
			case TypedExprDef.TEnumIndex(_):
				true;
			default:
				switch (subject.t) {
					case Type.TEnum(_, _):
						true;
					default:
						false;
				}
		};
		if (isEnumSwitch) {
			violation("V15", "EnumDefaultArm",
				"switch over an enum carries a default arm; enum switches list every variant",
				maybeDefault.pos);
		}
	}

	static function checkInt64(e:TypedExpr):Void {
		switch (e.t) {
			case Type.TAbstract(abstractRef, _):
				final definition = abstractRef.get();
				if (definition.module == "haxe.Int64") {
					final infos = Context.getPosInfos(e.pos);
					if (!int64Allowed(infos.file)) {
						violation("V11", "Int64Misuse",
							"haxe.Int64 appears outside the modules stdlib/05 permits",
							e.pos);
					}
				}
			default:
		}
	}

	static function int64Allowed(file:String):Bool {
		for (index in 0...INT64_MODULE_ALLOWLIST.length) {
			if (StringTools.startsWith(file, INT64_MODULE_ALLOWLIST[index])) {
				return true;
			}
		}
		return false;
	}

	static function violation(code:String, name:String, detail:String, position:Position):Void {
		Context.fatalError('$code $name: $detail', position);
	}
}
