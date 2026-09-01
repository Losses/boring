/**
 * Generation interception for the Haxe style standard,
 * docs/specs/style/01-haxe-style-standard.md. Registered from every compile
 * that feeds the pipeline: `--macro Intercept.run(['samples', 'tests/haxe'])`.
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
 *   V17 AssignArgExpression assignment expressions in call arguments     [pass 1]
 *   V18 NonAsciiStringIndex index access to non-ascii string literals   [1+2]
 *   V19 TryRegionControlFlow return, break, continue in a region body   [pass 2]
 *   V20 TryRegionMixedDomains region body throwing beyond the caught class [pass 2]
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
import haxe.macro.Type.TVar;
import ValueTypeSupport;

class Intercept {
	/** Field names whose call form is banned on any receiver (V02). */
	static final FUNCTIONAL_METHODS:Array<String> = [
		"map", "filter", "fold", "reduce", "forEach", "flatMap", "find", "some",
		"every", "sortedBy", "associate", "any", "all", "firstOrNull", "sumOfInt",
		"sumOfFloat", "mapNotNull", "groupBy",
	];

	/** Closed-list pipeline methods eligible for inline function literal exemption. */
	static final CLOSED_LIST:Array<String> = [
		"map", "filter", "forEach", "associate", "sortedBy",
		"any", "all", "firstOrNull", "sumOfInt", "sumOfFloat", "mapNotNull", "flatMap", "groupBy",
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

	/** String operations whose Rust lowering addresses bytes (V18). */
	static final STRING_INDEX_CALLEES:Array<String> = [
		"charCodeAt", "charAt", "codePointAt", "substring", "substr",
		"indexOf", "lastIndexOf",
	];

	/** Fields initialized from a string literal, keyed class:field (V18). */
	static var stringLiteralFields:Map<String, String> = new Map();

	/** Fields that receive an assignment somewhere, keyed class:field (V18). */
	static var reassignedFields:Map<String, Bool> = new Map();

	/** Locals of the field body under walk initialized from a string
	 * literal, keyed by TVar id (V18). */
	static var localStringLiterals:Map<Int, String> = new Map();

	/** Source ranges where spec 22 explicitly sanctions `new Map()`. */
	static var coalescingMapRanges:Array<{file:String, min:Int, max:Int}> = [];

	/**
	 * Files permitted to reference haxe.Int64 (V11): the FPHelper float
	 * conversion paths that docs/specs/stdlib/05-haxe-int64.md sanctions.
	 * The list is supplied by the registering compile; this file carries
	 * no sample paths.
	 */
	static var int64ModuleAllowlist:Array<String> = [];

	/** The source roots this run guards; targets scope compilation to them. */
	public static function sourceRoots():Array<String> {
		return roots.copy();
	}

	public static function run(rootPrefixes:Array<String>, int64Allowlist:Array<String>):Void {
		for (index in 0...rootPrefixes.length) {
			roots.push(rootPrefixes[index]);
		}
		for (index in 0...int64Allowlist.length) {
			int64ModuleAllowlist.push(int64Allowlist[index]);
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
		DefaultArgExpander.registerClassFields(classType, fields);
		// The Haxe typer represents a marked abstract's constructor as an
		// implementation class whose synthetic `this` assignments contain
		// target-less casts. Those casts are the wrapper representation, not
		// an untyped source escape (the value-type extension validates the
		// resulting typed members after typing).
		if (ValueTypeSupport.markedAbstractOfClass(classType) != null) {
			return fields;
		}
		for (index in 0...fields.length) {
			final field = fields[index];
			switch (field.kind) {
				case FieldType.FVar(_, expression):
					if (expression != null) {
						walkSource(expression);
						walkStringIndexSource(expression, [new Map<String, String>()]);
					}
				case FieldType.FProp(_, _, _, expression):
					if (expression != null) {
						walkSource(expression);
						walkStringIndexSource(expression, [new Map<String, String>()]);
					}
				case FieldType.FFun(fun):
					if (fun.expr != null) {
						walkSource(fun.expr);
						final parameterScope = new Map<String, String>();
						for (argument in fun.args) {
							parameterScope.set(argument.name, "");
						}
						walkStringIndexSource(fun.expr, [parameterScope]);
					}
			}
		}
		return fields;
	}

	/**
	 * V18, call forms, pass 1. The typer expands the inline std String
	 * methods (`charCodeAt` becomes an `HxOverrides.cca` call on the
	 * JavaScript std), so the typed tree no longer carries these calls; the
	 * untyped tree is the only layer where they survive every target. The
	 * walker tracks block scopes and binds a name to its non-ascii literal
	 * only when the declaration is final, so reassignment and shadowing by
	 * any later declaration clear the binding. An empty string marks a
	 * declared name with no non-ascii literal.
	 */
	static function walkStringIndexSource(e:Expr, scopes:Array<Map<String, String>>):Void {
		// The Haxe parser represents an empty `switch` default arm as a
		// placeholder object whose expr and pos are both null instead of a
		// null reference; the std ExprTools.iter skips that placeholder with
		// the same `edef.expr != null` check. Source never writes this shape,
		// so any node carrying it holds no names to track.
		if (e == null || e.expr == null) {
			return;
		}
		switch (e.expr) {
			case ExprDef.EBlock(expressions):
				scopes.push(new Map<String, String>());
				for (child in expressions) {
					walkStringIndexSource(child, scopes);
				}
				scopes.pop();
			case ExprDef.EVars(vars):
				final scope = scopes[scopes.length - 1];
				for (variable in vars) {
					final literal = variable.isFinal ? nonAsciiLiteralOf(variable.expr) : null;
					scope.set(variable.name, literal == null ? "" : literal);
				}
				ExprTools.iter(e, (child:Expr) -> {
					walkStringIndexSource(child, scopes);
				});
			case ExprDef.EFunction(_, func):
				final scope = new Map<String, String>();
				for (argument in func.args) {
					scope.set(argument.name, "");
				}
				scopes.push(scope);
				walkStringIndexSource(func.expr, scopes);
				scopes.pop();
			case ExprDef.EFor(iterator, body):
				final scope = new Map<String, String>();
				switch (iterator.expr) {
					case ExprDef.EBinop(Binop.OpIn, element, _):
						switch (element.expr) {
							case ExprDef.EConst(Constant.CIdent(name)):
								scope.set(name, "");
							default:
						}
					default:
				}
				scopes.push(scope);
				walkStringIndexSource(body, scopes);
				scopes.pop();
			case ExprDef.ETry(body, catches):
				walkStringIndexSource(body, scopes);
				for (catcher in catches) {
					final scope = new Map<String, String>();
					scope.set(catcher.name, "");
					scopes.push(scope);
					walkStringIndexSource(catcher.expr, scopes);
					scopes.pop();
				}
			case ExprDef.ESwitch(_, cases, defaultExpression):
				for (switchCase in cases) {
					scopes.push(new Map<String, String>());
					walkStringIndexSource(switchCase.expr, scopes);
					scopes.pop();
				}
				if (defaultExpression != null) {
					scopes.push(new Map<String, String>());
					walkStringIndexSource(defaultExpression, scopes);
					scopes.pop();
				}
			case ExprDef.ECall(callee, args):
				checkStringIndexSourceCall(callee, args, scopes);
				ExprTools.iter(e, (child:Expr) -> {
					walkStringIndexSource(child, scopes);
				});
			default:
				ExprTools.iter(e, (child:Expr) -> {
					walkStringIndexSource(child, scopes);
				});
		}
	}

	static function checkStringIndexSourceCall(callee:Expr, args:Array<Expr>, scopes:Array<Map<String, String>>):Void {
		switch (callee.expr) {
			case ExprDef.EField(subject, field):
				switch (subject.expr) {
					case ExprDef.EConst(Constant.CIdent("StringTools")):
						if (field == "fastCodeAt") {
							violation("V18", "NonAsciiStringIndex",
								"StringTools.fastCodeAt reads storage units with no content meaning; use std.UString.at", subject.pos);
						}
						if (field == "fromCharCode") {
							violation("V18", "NonAsciiStringIndex",
								"StringTools.fromCharCode writes one utf-16 code unit; use std.UString.fromCodePoint", subject.pos);
						}
					default:
				}
				if (isStringIndexCallee(field)) {
					final target = parenStripped(subject);
					switch (target.expr) {
						case ExprDef.EConst(Constant.CString(literal)):
							if (!isAsciiOnly(literal)) {
								violation("V18", "NonAsciiStringIndex",
									"string index access requires ascii content; non-ascii content uses std.UString: " + field, target.pos);
							}
						case ExprDef.EConst(Constant.CIdent(name)):
							final literal = scopedNonAsciiLiteral(name, scopes);
							if (literal != null) {
								violation("V18", "NonAsciiStringIndex",
									"string index access requires ascii content; non-ascii content uses std.UString: " + field, target.pos);
							}
						default:
					}
				}
				if (field == "fromCharCode") {
					switch (subject.expr) {
						case ExprDef.EConst(Constant.CIdent("String")):
							if (args.length > 0) {
								switch (args[0].expr) {
									case ExprDef.EConst(Constant.CInt(value)):
										final code = Std.parseInt(value);
										if (code == null || code < 0 || code > 0xFF) {
											violation("V18", "NonAsciiStringIndex",
												"String.fromCharCode accepts wire bytes 0..255; code points use std.UString.fromCodePoint", args[0].pos);
										}
									default:
								}
							}
						default:
					}
				}
			default:
		}
	}

	static function nonAsciiLiteralOf(init:Null<Expr>):Null<String> {
		if (init == null) {
			return null;
		}
		switch (init.expr) {
			case ExprDef.EConst(Constant.CString(literal)):
				return isAsciiOnly(literal) ? null : literal;
			default:
				return null;
		}
	}

	static function scopedNonAsciiLiteral(name:String, scopes:Array<Map<String, String>>):Null<String> {
		var depth = scopes.length - 1;
		while (depth >= 0) {
			final scope = scopes[depth];
			if (scope.exists(name)) {
				final literal = scope.get(name);
				return literal.length > 0 ? literal : null;
			}
			depth--;
		}
		return null;
	}

	static function parenStripped(e:Expr):Expr {
		switch (e.expr) {
			case ExprDef.EParenthesis(inner):
				return parenStripped(inner);
			default:
				return e;
		}
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
				checkAssignArgExpression(callee, args);
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

	static function isCopyCallee(callee:Expr):Bool {
		return switch (callee.expr) {
			case ExprDef.EField(_, "copy"): true;
			case ExprDef.EConst(Constant.CIdent("copy")): true;
			default: false;
		};
	}

	static function isAssignArg(arg:Expr):Bool {
		return switch (arg.expr) {
			case ExprDef.EBinop(Binop.OpAssign, _, _): true;
			case ExprDef.EParenthesis(inner): isAssignArg(inner);
			default: false;
		};
	}

	static function checkAssignArgExpression(callee:Expr, args:Array<Expr>):Void {
		if (isCopyCallee(callee)) {
			return;
		}
		for (index in 0...args.length) {
			final arg = args[index];
			if (isAssignArg(arg)) {
				violation("V17", "AssignArgExpression",
					"assignment expressions in call arguments belong to the record copy construct only",
					arg.pos);
			}
		}
	}

	static function isFunctionLiteral(e:Expr):Bool {
		if (e == null) {
			return false;
		}
		return switch (e.expr) {
			case ExprDef.EFunction(_, _): true;
			case ExprDef.EParenthesis(inner): isFunctionLiteral(inner);
			default: false;
		};
	}

	static function isClosedListMethod(name:String):Bool {
		for (index in 0...CLOSED_LIST.length) {
			if (name == CLOSED_LIST[index]) {
				return true;
			}
		}
		return false;
	}

	static function checkSourceCall(callee:Expr, args:Array<Expr>):Void {
		switch (callee.expr) {
			case ExprDef.EField(receiver, name):
				if(name == "allEnums" || name == "enumConstructor" || name == "createEnum") {
					switch(receiver.expr) {
						case ExprDef.EConst(Constant.CIdent("Type")):
							if(name == "createEnum" && args.length != 2) Context.fatalError("Type.createEnum accepts the two-argument form only", callee.pos);
							if(name == "allEnums" && (args.length != 1 || switch(args[0].expr) { case ExprDef.EConst(Constant.CIdent(_)): false; case _: true; })) Context.fatalError("Type.allEnums accepts an enum type reference only", callee.pos);
							if(name == "createEnum" && switch(args[0].expr) { case ExprDef.EConst(Constant.CIdent(_)): false; case _: true; }) Context.fatalError("Type.createEnum accepts the two-argument form only", callee.pos);
							return;
						default:
					}
				}
				if (name == "sort") {
					if (args.length > 0) {
						violation("V02", "FunctionalIteration",
							"comparator sort rewrites to a plain loop before translation; the exit is the sort runtime of features/17",
							callee.pos);
					}
					return;
				}
				if (isClosedListMethod(name)) {
					if (args.length == 1 && isFunctionLiteral(args[0])) {
						return;
					}
					Context.fatalError("collection pipeline methods accept inline function literals only", callee.pos);
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
		// Phase one records string literal field initializers and every
		// field that receives an assignment, so the V18 subject resolution
		// reads facts regardless of module order and skips mutable fields.
		for (index in 0...modules.length) {
			switch (modules[index]) {
				case haxe.macro.Type.ModuleType.TClassDecl(classRef):
					final classType = classRef.get();
					if (!isGuarded(classType.pos)) {
						continue;
					}
					recordFieldIndexFacts(classType, classType.fields.get());
					recordFieldIndexFacts(classType, classType.statics.get());
				default:
			}
		}
		for (index in 0...modules.length) {
			switch (modules[index]) {
				case haxe.macro.Type.ModuleType.TClassDecl(classRef):
					final classType = classRef.get();
					if (!isGuarded(classType.pos)) {
						continue;
					}
					checkDataInheritance(classType);
					walkClassFields(classType, classType.fields.get());
					walkClassFields(classType, classType.statics.get());
				default:
			}
		}
	}

	static function recordFieldIndexFacts(classType:ClassType, fields:Array<ClassField>):Void {
		for (index in 0...fields.length) {
			final field = fields[index];
			if (field.expr == null) {
				continue;
			}
			final body = field.expr();
			if (body == null) {
				continue;
			}
			switch (body.expr) {
				case TypedExprDef.TConst(TString(literal)):
					if (isStringType(field.type)) {
						stringLiteralFields.set(fieldKeyOf(classType, field.name), literal);
					}
				default:
			}
			collectIndexFacts(body, new Map<Int, String>(), new Map<Int, Bool>());
		}
	}

	static function walkClassFields(classType:haxe.macro.Type.ClassType, fields:Array<ClassField>):Void {
		for (index in 0...fields.length) {
			final field = fields[index];
			if (field.expr == null) {
				continue;
			}
			final body = field.expr();
			if (body == null) {
				continue;
			}
			DefaultArgExpander.completeRootExpr(classType, field.name, body);
			PipelineExpander.expandRootExpr(body);
			EnumQueryExpander.expandRootExpr(body);
			localStringLiterals = collectLocalStringLiterals(body);
			coalescingMapRanges = [];
			for (site in DefaultArgExpander.coalescingSites(body)) {
				if (!DefaultArgExpander.isRegisteredCoalescingSource(site.defaultExpr.pos)) {
					continue;
				}
				final pos = Context.getPosInfos(site.defaultExpr.pos);
				coalescingMapRanges.push({file: pos.file, min: pos.min, max: pos.max});
			}
			walk(body, false);
			coalescingMapRanges = [];
		}
	}

	/**
	 * Collects the V18 resolution facts of one body: locals initialized from
	 * a string literal, minus locals that receive an assignment anywhere in
	 * the body. Field targets reached by assignment land in the shared
	 * reassignedFields map, which phase one of walkModules seeds.
	 */
	static function collectIndexFacts(e:TypedExpr, literals:Map<Int, String>, reassignedLocals:Map<Int, Bool>):Void {
		if (e == null) {
			return;
		}
		switch (e.expr) {
			case TypedExprDef.TVar(variable, init):
				if (init != null) {
					switch (init.expr) {
						case TypedExprDef.TConst(TString(literal)):
							if (isStringType(variable.t)) {
								literals.set(variable.id, literal);
							}
						default:
					}
				}
			case TypedExprDef.TBinop(binaryOperator, target, _):
				switch (binaryOperator) {
					case Binop.OpAssign | Binop.OpAssignOp(_):
						switch (target.expr) {
							case TypedExprDef.TLocal(variable):
								reassignedLocals.set(variable.id, true);
							case TypedExprDef.TField(_, FieldAccess.FStatic(classRef, fieldRef))
								| TypedExprDef.TField(_, FieldAccess.FInstance(classRef, _, fieldRef)):
								reassignedFields.set(fieldKeyOf(classRef.get(), fieldRef.get().name), true);
							default:
						}
					default:
				}
			default:
		}
		haxe.macro.TypedExprTools.iter(e, (child:TypedExpr) -> {
			collectIndexFacts(child, literals, reassignedLocals);
		});
	}

	static function collectLocalStringLiterals(root:TypedExpr):Map<Int, String> {
		final literals = new Map<Int, String>();
		final reassignedLocals = new Map<Int, Bool>();
		collectIndexFacts(root, literals, reassignedLocals);
		for (key in literals.keys()) {
			if (reassignedLocals.exists(key)) {
				literals.remove(key);
			}
		}
		return literals;
	}

	static function fieldKeyOf(classType:ClassType, fieldName:String):String {
		return DefaultArgExpander.classKeyOf(classType) + ":" + fieldName;
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
				checkRegion(e, body, catches, inLoop);
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
		// typed Dynamic by that machinery, not by the source. The expanded
		// form nests one call below the js.Syntax field, as in
		// code("isFinite")(f) from js/_std/Math.hx, so a callee that is
		// itself a js.Syntax call is plumbing too.
		final skipDynamicCheck = switch (e.expr) {
			case TypedExprDef.TThrow(_)
				| TypedExprDef.TReturn(_)
				| TypedExprDef.TBreak
				| TypedExprDef.TContinue
				| TypedExprDef.TBlock(_)
				| TypedExprDef.TCast(_, _):
				true;
			case TypedExprDef.TCall(callee, _):
				isSyntaxPlumbingCall(callee) || isNestedSyntaxPlumbingCall(callee);
			default:
				false;
		};
		if (!skipDynamicCheck) {
			checkDynamic(e);
		}
		checkMapType(e);
		checkInt64(e);
		checkStringIndex(e);
	}

	/**
	 * Region rules of features/06: one clause, one domain, and no control
	 * flow crossing the region boundary (V19, V20).
	 */
	static function checkRegion(region:TypedExpr, body:TypedExpr,
			catches:Array<{v:TVar, expr:TypedExpr}>, inLoop:Bool):Void {
		if (catches.length != 1) {
			violation("V20", "TryRegionMixedDomains",
				"try region handles exactly one exception domain; nest one region per domain",
				region.pos);
		} else {
			final catchVariable = catches[0].v;
			switch (catchVariable.t) {
				case Type.TDynamic(_):
					violation("V14", "DynamicCatch",
						"catch variable is typed Dynamic; catch clauses name the exception type",
						region.pos);
				case Type.TInst(classRef, _):
					final cls = classRef.get();
					if (!isEnumCarryingException(cls)) {
						violation("V20", "TryRegionMixedDomains",
							"try region catch type carries no payload enum",
							region.pos);
					} else {
						checkRegionDomains(body, cls.module, []);
					}
				default:
					violation("V20", "TryRegionMixedDomains",
						"try region catch type carries no payload enum",
						region.pos);
			}
		}
		checkRegionControlFlow(body, false);
		walk(body, inLoop);
		for (index in 0...catches.length) {
			walk(catches[index].expr, inLoop);
		}
	}

	/**
	 * A throw of a class the region does not catch escapes the region, so
	 * the single closure error type of the Rust lowering breaks (V20).
	 * Nested regions absorb their own domains inside their bodies; their
	 * handlers throw into the enclosing region.
	 */
	static function checkRegionDomains(e:TypedExpr, caughtModule:String, absorbed:Array<String>):Void {
		switch (e.expr) {
			case TypedExprDef.TThrow(inner):
				switch (inner.t) {
					case Type.TInst(classRef, _):
						final module = classRef.get().module;
						if (module != caughtModule && absorbed.indexOf(module) < 0) {
							violation("V20", "TryRegionMixedDomains",
								"try region body throws " + classRef.get().name
								+ " beyond the caught class; nest one region per domain",
								e.pos);
						}
					default:
						// V04 rejects the throw itself.
				}
			case TypedExprDef.TTry(nestedBody, nestedCatches):
				final nestedAbsorbed = absorbed.slice(0, absorbed.length);
				for (index in 0...nestedCatches.length) {
					switch (nestedCatches[index].v.t) {
						case Type.TInst(classRef, _):
							nestedAbsorbed.push(classRef.get().module);
						default:
					}
					checkRegionDomains(nestedCatches[index].expr, caughtModule, absorbed);
				}
				checkRegionDomains(nestedBody, caughtModule, nestedAbsorbed);
			default:
				haxe.macro.TypedExprTools.iter(e, (child:TypedExpr) -> {
					checkRegionDomains(child, caughtModule, absorbed);
				});
		}
	}

	/**
	 * return, break, and continue crossing the region boundary cannot lower
	 * through the Rust closure (V19). Loops inside the body rebind their own
	 * break and continue; a local function body binds its own return.
	 */
	static function checkRegionControlFlow(e:TypedExpr, inLoop:Bool):Void {
		switch (e.expr) {
			case TypedExprDef.TReturn(_):
				violation("V19", "TryRegionControlFlow",
					"return inside a try region body; hoist the region and return after it",
					e.pos);
			case TypedExprDef.TBreak if(!inLoop):
				violation("V19", "TryRegionControlFlow",
					"break inside a try region body; hoist the region and break after it",
					e.pos);
			case TypedExprDef.TContinue if(!inLoop):
				violation("V19", "TryRegionControlFlow",
					"continue inside a try region body; hoist the region and continue after it",
					e.pos);
			case TypedExprDef.TWhile(condition, body, _):
				checkRegionControlFlow(condition, inLoop);
				checkRegionControlFlow(body, true);
			case TypedExprDef.TFor(_, subject, body):
				checkRegionControlFlow(subject, inLoop);
				checkRegionControlFlow(body, true);
			case TypedExprDef.TFunction(_):
				// return inside a local function binds to that function.
			case TypedExprDef.TTry(nestedBody, nestedCatches):
				checkRegionControlFlow(nestedBody, false);
				for (index in 0...nestedCatches.length) {
					checkRegionControlFlow(nestedCatches[index].expr, inLoop);
				}
			default:
				haxe.macro.TypedExprTools.iter(e, (child:TypedExpr) -> {
					checkRegionControlFlow(child, inLoop);
				});
		}
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
			case TypedExprDef.TCall(innerCallee, _):
				// js/_std/Math.hx inlines members such as isNaN as a curried
				// application: code("isNaN")(f). The outer call node is typed
				// Dynamic by the same js.Syntax machinery as the direct form,
				// so the skip follows the callee chain one level down.
				return isSyntaxPlumbingCall(innerCallee);
			default:
				return false;
		}
	}

	/**
	 * Outer call of the two-layer expansion code("...")(arg): the callee is
	 * the inner call whose callee is the js.Syntax static field. Extern
	 * inlines such as Math.isFinite and Math.isNaN on the js target expand
	 * to this shape.
	 */
	static function isNestedSyntaxPlumbingCall(callee:TypedExpr):Bool {
		switch (callee.expr) {
			case TypedExprDef.TCall(inner, _):
				return isSyntaxPlumbingCall(inner);
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

	/**
	 * V18. The Rust runtime addresses String as UTF-8 bytes while the other
	 * three sides address UTF-16 code units, so index operations carry an
	 * ASCII-bounded contract. The check fires only on subjects that resolve
	 * to a string literal, where non-ASCII content is a compile-time fact;
	 * runtime-built strings stay under the consistency harness.
	 */
	static function checkStringIndex(e:TypedExpr):Void {
		switch (e.expr) {
			case TypedExprDef.TField(subj, fieldAccess):
				if (fieldNameOf(fieldAccess) == "length" && isStringType(subj.t)) {
					checkAsciiIndexSubject(subj, "length");
				}
			case TypedExprDef.TCall(callee, args):
				switch (callee.expr) {
					case TypedExprDef.TField(subj, fieldAccess):
						final name = fieldNameOf(fieldAccess);
						if (isStringIndexCallee(name) && isStringType(subj.t)) {
							checkAsciiIndexSubject(subj, name);
						}
						if (isStringFromCharCode(fieldAccess) && args.length > 0) {
							checkFromCharCodeArgument(args[0]);
						}
					default:
				}
			default:
		}
	}

	static function fieldNameOf(fieldAccess:FieldAccess):Null<String> {
		return switch (fieldAccess) {
			case FieldAccess.FInstance(_, _, fieldRef) | FieldAccess.FAnon(fieldRef):
				fieldRef.get().name;
			case FieldAccess.FStatic(_, fieldRef) | FieldAccess.FClosure(_, fieldRef):
				fieldRef.get().name;
			case FieldAccess.FEnum(_, enumField):
				enumField.name;
			case FieldAccess.FDynamic(name):
				name;
		};
	}

	static function isStringIndexCallee(name:Null<String>):Bool {
		if (name == null) {
			return false;
		}
		return STRING_INDEX_CALLEES.indexOf(name) >= 0;
	}

	static function isStringType(t:Type):Bool {
		return switch (t) {
			case Type.TInst(classRef, _):
				final classType = classRef.get();
				classType.pack.length == 0 && classType.name == "String";
			default:
				false;
		};
	}

	static function isStringFromCharCode(fieldAccess:FieldAccess):Bool {
		return switch (fieldAccess) {
			case FieldAccess.FStatic(classRef, fieldRef):
				final classType = classRef.get();
				classType.pack.length == 0 && classType.name == "String" && fieldRef.get().name == "fromCharCode";
			default:
				false;
		};
	}

	static function checkAsciiIndexSubject(subj:TypedExpr, op:String):Void {
		final literal = stringLiteralOf(subj);
		if (literal != null && !isAsciiOnly(literal)) {
			violation("V18", "NonAsciiStringIndex",
				"string index access requires ascii content; non-ascii content uses std.UString: " + op, subj.pos);
		}
	}

	static function stringLiteralOf(subj:TypedExpr):Null<String> {
		switch (subj.expr) {
			case TypedExprDef.TConst(TString(literal)):
				return literal;
			case TypedExprDef.TLocal(variable):
				return localStringLiterals.get(variable.id);
			case TypedExprDef.TField(_, FieldAccess.FStatic(classRef, fieldRef))
				| TypedExprDef.TField(_, FieldAccess.FInstance(classRef, _, fieldRef)):
				final key = fieldKeyOf(classRef.get(), fieldRef.get().name);
				return reassignedFields.exists(key) ? null : stringLiteralFields.get(key);
			default:
				return null;
		}
	}

	static function isAsciiOnly(value:String):Bool {
		for (index in 0...value.length) {
			if (value.charCodeAt(index) > 0x7F) {
				return false;
			}
		}
		return true;
	}

	static function checkFromCharCodeArgument(arg:TypedExpr):Void {
		switch (arg.expr) {
			case TypedExprDef.TConst(TInt(code)):
				if (code < 0 || code > 0xFF) {
					violation("V18", "NonAsciiStringIndex",
						"String.fromCharCode accepts wire bytes 0..255; code points use std.UString.fromCodePoint", arg.pos);
				}
			default:
		}
	}

	static function checkMapType(e:TypedExpr):Void {
		if (isInCoalescingMapRange(e.pos)) {
			return;
		}
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

	static function isInCoalescingMapRange(pos:Position):Bool {
		final infos = Context.getPosInfos(pos);
		for (range in coalescingMapRanges) {
			if (range.file == infos.file && infos.min >= range.min && infos.max <= range.max) {
				return true;
			}
		}
		return false;
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
		for (index in 0...int64ModuleAllowlist.length) {
			if (StringTools.startsWith(file, int64ModuleAllowlist[index])) {
				return true;
			}
		}
		return false;
	}

	static function violation(code:String, name:String, detail:String, position:Position):Void {
		Context.fatalError('$code $name: $detail', position);
	}
}
