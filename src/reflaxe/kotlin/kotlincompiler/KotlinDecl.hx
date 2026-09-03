package kotlincompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.data.ClassFuncData;
import reflaxe.data.ClassVarData;
import reflaxe.data.EnumOptionData;
import ValueTypeSupport;
import ValueTypeSupport.ValueTypeOperator;
import ValueTypeSupport.ValueTypeInfo;

/**
	Declaration lowering for Kotlin: classes, objects, sealed error
	hierarchies, and data classes. Every emission derives from the typed
	AST; the exception fold reads the payload enum's options and the
	message function's switch cases.
**/
class KotlinDecl {
	final imports: KotlinImports;
	final types: KotlinType;
	final expr: KotlinExpr;

	public function new(selfModule: String, state: KotlinEmissionState) {
		this.imports = new KotlinImports(selfModule, state);
		this.types = new KotlinType(imports, state);
		this.expr = new KotlinExpr(imports, types, state);
	}

	public function renderImports(): String {
		return imports.render();
	}

	public function topLevelStatements(e: TypedExpr): String {
		return expr.topLevelStatements(e);
	}

	public function rawExpression(e: TypedExpr): String {
		return expr.rawExpression(e);
	}

	// ------------------------------------------------------------------
	// Classes & Objects
	// ------------------------------------------------------------------

	public function classDecl(cls: ClassType, varFields: Array<ClassVarData>, funcFields: Array<ClassFuncData>): String {
		// Kotlin's data class already supplies the same printed form while
		// its parameter order matches the field declaration order. The
		// stage 1 build macro marks its synthetic member so this target can
		// drop it; a reordered class keeps the member as an explicit
		// override (feature spec 37 rule 3).
		funcFields = [for(f in funcFields) if(!isSynthesizedRecordToString(cls, f)) f];
		if(cls.isInterface) {
			final lines: Array<String> = [];
			final sealed = SealedVariantHelper.isSealedInterface(cls) ? "sealed " : "";
			lines.push(sealed + "interface " + cls.name + " {");
			for(f in funcFields) {
				final args = [for(a in f.args) {
					final coalescing = DefaultArgExpander.coalescingDefaultAt(cls, f.field.name, a.index);
					final parameterType = coalescing != null ? DefaultArgExpander.coalescingParameterType(coalescing, a.type) : a.type;
					final defaultText = coalescing != null ? " = " + expr.coalescingDefaultText(coalescing, a.type) : "";
					'${a.name}: ${types.of(parameterType)}$defaultText';
				}].join(", ");
				final retType = types.of(f.ret);
				final ret = retType == "Unit" ? "" : ": " + retType;
				lines.push('    fun ${f.field.name}($args)$ret');
			}
			lines.push("}");
			return lines.join("\n");
		}

		if(isExceptionSubclass(cls)) {
			final payload = payloadEnumOf(funcFields);
			if(payload == null) {
				Context.error("exception subclass without a payload enum constructor has no Kotlin lowering", cls.pos);
				return null;
			}
			return sealedExceptionDecl(cls, payload, funcFields);
		}

		var hasTestMethods = false;
		for(f in funcFields) {
			if(f.field.meta.has(":test")) {
				hasTestMethods = true;
				break;
			}
		}

		if(hasTestMethods) {
			// Test classes carry test functions and nothing else (feature
			// spec 27); shared logic belongs in an ordinary class, whose
			// member lowering every target already renders.
			for(v in varFields) {
				Context.error("test class " + cls.name + " carries a non-test member " + v.field.name + "; shared logic belongs in an ordinary class", v.field.pos);
			}
			final lines: Array<String> = [];
			lines.push("class " + cls.name + " {");
			var sep = false;
			final sortedFuncs = funcFields.copy();
			sortedFuncs.sort((a, b) -> Reflect.compare(Context.getPosInfos(a.field.pos).min, Context.getPosInfos(b.field.pos).min));
			for(f in sortedFuncs) {
				if(!f.field.meta.has(":test")) {
					Context.error("test class " + cls.name + " carries a non-test member " + f.field.name + "; shared logic belongs in an ordinary class", f.field.pos);
				}
				if(sep) lines.push("");
				sep = true;
				for(l in testFuncDecl(cls, f)) lines.push(l);
			}
			lines.push("}");
			return lines.join("\n");
		}

		final extractedFuncs = [for(f in funcFields) if(StaticFunctionMarkers.isMarked(f.field)) f];
		final ordinaryFuncs = [for(f in funcFields) if(!StaticFunctionMarkers.isMarked(f.field)) f];
		final extractedParts: Array<String> = [];
		for(f in extractedFuncs) {
			extractedParts.push(extractedFuncDecl(cls, f).join("\n"));
		}
		if(varFields.length == 0 && ordinaryFuncs.length == 0) {
			return extractedParts.join("\n\n");
		}

		final isObject = isAllStatic(varFields, ordinaryFuncs);
		final lines: Array<String> = [];

		if(isObject) {
			lines.push("object " + cls.name + " {");
			for(v in varFields) {
				for(l in objectVarDecl(v, cls)) lines.push(l);
			}
			var sep = varFields.length > 0 && ordinaryFuncs.length > 0;
			for(f in ordinaryFuncs) {
				if(sep) lines.push("");
				sep = true;
				for(l in funcDecl(cls, f, true)) lines.push(l);
			}
			lines.push("}");
			return withExtracted(extractedParts, lines.join("\n"));
		}

		// Instance class
		final constructorFunc = findConstructor(funcFields);
		final constructorArgNames: Map<String, Bool> = [];
		if(constructorFunc != null) {
			for(a in constructorFunc.args) {
				constructorArgNames.set(a.name, true);
			}
		}

		final ctorHeader = constructorFunc != null ? buildPrimaryConstructor(cls, constructorFunc, varFields) : "";
		final ifaceStr = cls.interfaces.length > 0 ? " : " + [for(i in cls.interfaces) i.t.get().name].join(", ") : "";
		final classParams = cls.params.length > 0 ? "<" + [for(p in cls.params) p.name].join(", ") + ">" : "";
		// @:dataClass opts into the Kotlin data class prefix (feature spec 27);
		// every constructor parameter must be a field for the synthesized
		// copy/equals/printed form to cover the whole state.
		final isDataClass = cls.meta.has(":dataClass");
		if(isDataClass) {
			if(constructorFunc == null || constructorFunc.args.length == 0) {
				Context.error("@:dataClass requires at least one constructor parameter", cls.pos);
			}
			for(a in constructorFunc.args) {
				var isField = false;
				for(v in varFields) {
					if(v.field.name == a.name) {
						isField = true;
						break;
					}
				}
				if(!isField) {
					Context.error("@:dataClass requires every constructor parameter to be a class field", cls.pos);
				}
			}
		}
		lines.push((isDataClass ? "data " : "") + "class " + cls.name + classParams + ctorHeader + ifaceStr + " {");

		// Constructor body renders into one init block (feature spec 27).
		// Parameter self-assignments are implicit in the primary
		// constructor and drop out; assignments to fields the constructor
		// does not receive as parameters initialize those fields here, so
		// their declarations carry no initializer. Kotlin requires the
		// stored-property declarations to precede the init block's
		// assignments, so the block follows the declarations.
		final ctorInit = constructorFunc != null && constructorFunc.expr != null
			? expr.initBlockStatements(cls, constructorFunc)
			: {lines: [], assigned: []};

		// Stored properties without a constructor parameter; getter-only
		// properties keep no storage (feature spec 27).
		for(v in varFields) {
			if(v.isStatic) {
				continue;
			}
			if(constructorArgNames.exists(v.field.name) || isGetterOnlyProperty(v.field)) {
				continue;
			}
			if(ctorInit.assigned.indexOf(v.field.name) >= 0) {
				lines.push('    ${(v.field.isFinal ? "val" : "var")} ${v.field.name}: ${types.of(v.field.type)}');
			} else {
				for(l in classVarDecl(v)) lines.push(l);
			}
		}

		for(l in ctorInitBlock(ctorInit.lines)) lines.push(l);

		// Getter-only property facade (feature spec 27): var x(get, never)
		// with the standard read accessor renders a Kotlin property beside
		// the generated get_x function, so consumers use property syntax for
		// computed and stored values alike.
		for(field in cls.fields.get()) {
			if(!isGetterOnlyProperty(field)) {
				continue;
			}
			var hasInstanceGetter = false;
			for(f in funcFields) {
				if(!f.isStatic && f.field.name == "get_" + field.name) {
					hasInstanceGetter = true;
					break;
				}
			}
			if(hasInstanceGetter) {
				final vis = field.isPublic ? "" : "private ";
				lines.push('    ${vis}val ${field.name}: ${types.of(field.type)} get() = get_${field.name}()');
			}
		}

		final instanceFuncs = [for(f in ordinaryFuncs) if(!f.isStatic && f.field.name != "new") f];
		final staticFuncs = [for(f in ordinaryFuncs) if(f.isStatic) f];
		final staticVars = [for(v in varFields) if(v.isStatic && !isFunctionType(v.field.type)) v];
		final staticFunctionVars = [for(v in varFields) if(v.isStatic && isFunctionType(v.field.type)) v];

		var sep = varFields.length > 0 && instanceFuncs.length > 0;
		for(f in instanceFuncs) {
			if(sep) lines.push("");
			sep = true;
			for(l in funcDecl(cls, f, false)) lines.push(l);
		}

		if(staticVars.length > 0 || staticFuncs.length > 0 || staticFunctionVars.length > 0) {
			if(instanceFuncs.length > 0 || varFields.length > 0) lines.push("");
			lines.push("    companion object {");
			var csep = false;
			for(v in staticVars) {
				if(csep) lines.push("");
				csep = true;
				for(l in objectVarDecl(v, cls)) lines.push("    " + l);
			}
			for(v in staticFunctionVars) {
				if(csep) lines.push("");
				csep = true;
				for(l in staticFunctionVarDecl(v)) lines.push("    " + l);
			}
			for(f in staticFuncs) {
				if(csep) lines.push("");
				csep = true;
				for(l in funcDecl(cls, f, true)) lines.push("    " + l);
			}
			lines.push("    }");
		}

		lines.push("}");
		final result = withExtracted(extractedParts, lines.join("\n"));
		return cls.meta.has(":dataClass") && KotlinType.canEmitDataClassComparator(cls) ? result + "\n\n" + dataClassComparator(cls) : result;
	}

	function dataClassComparator(cls: ClassType): String {
		final lines: Array<String> = [];
		final fields = [for(x in cls.fields.get()) if(switch(x.kind) { case FVar(read, write): !(read.match(AccCall) && write.match(AccNever)); case _: false; }) x];
		for(f in fields) {
			switch(f.type) {
				case TAbstract(a, params) if(a.get().name == "ReadOnlyArray" && params.length == 1):
					switch(Context.follow(params[0])) { case TEnum(e, _): final en = e.get(); lines.push('    fun ${cls.name}${f.name}Order(v: ${en.name}): Int = when (v) {'); for(ef in en.constructs) lines.push(enumFieldParams(ef).length > 0 ? '        is ${en.name}.${ef.name} -> ${ef.index}' : '        ${en.name}.${ef.name} -> ${ef.index}'); lines.push('    }'); case _: }
				default:
			}
			switch(Context.follow(f.type)) {
				case TEnum(e, _):
					final en = e.get();
					lines.push('    fun ${cls.name}${f.name}Order(v: ${en.name}): Int = when (v) {');
					for(ef in en.constructs) lines.push(enumFieldParams(ef).length > 0 ? '        is ${en.name}.${ef.name} -> ${ef.index}' : '        ${en.name}.${ef.name} -> ${ef.index}');
					lines.push('    }');
				case _:
			}
		}
		lines.push('    fun compare${cls.name}(a: ${cls.name}, b: ${cls.name}): Int {');
		lines.push('    var cmp = 0');
		for(f in fields) {
			// Context.follow unwraps Null, so nullable fields must be handled from the raw type.
			switch(f.type) {
				case TAbstract(a, params) if(a.get().name == "Null" && params.length == 1):
					lines.push('    if (a.${f.name} == null && b.${f.name} != null) return -1');
					lines.push('    if (a.${f.name} != null && b.${f.name} == null) return 1');
					switch(Context.follow(params[0])) {
						case TEnum(e, _): lines.push('    if (a.${f.name} != null && b.${f.name} != null) { cmp = ${cls.name}${f.name}Order(a.${f.name}).compareTo(${cls.name}${f.name}Order(b.${f.name})); if (cmp != 0) return cmp }');
						case TAbstract(_, _) | TInst(_, _): lines.push('    if (a.${f.name} != null && b.${f.name} != null) { cmp = a.${f.name}!!.compareTo(b.${f.name}!!); if (cmp != 0) return cmp }');
						case _: lines.push('    if (a.${f.name} != null && b.${f.name} != null) { cmp = a.${f.name}!!.toString().compareTo(b.${f.name}!!.toString()); if (cmp != 0) return cmp }');
					}
					continue;
				case TAbstract(a, params) if(a.get().pack.join(".") == "std" && a.get().name == "ReadOnlyArray" && params.length == 1):
					final element = params[0];
					lines.push('    var idx${f.name} = 0');
					lines.push('    while (idx${f.name} < a.${f.name}.size && idx${f.name} < b.${f.name}.size) {');
					switch(Context.follow(element)) {
						case TInst(c, _) if(c.get().meta.has(":dataClass")): imports.requireType(c.get().module, "compare" + c.get().name); lines.push('        cmp = compare${c.get().name}(a.${f.name}[idx${f.name}], b.${f.name}[idx${f.name}])');
						// The order helper is hoisted by the pre-pass over the
						// fields; emitting it here would nest a fun inside
						// the while loop body.
						case TEnum(e, _): lines.push('        cmp = ${cls.name}${f.name}Order(a.${f.name}[idx${f.name}]).compareTo(${cls.name}${f.name}Order(b.${f.name}[idx${f.name}]))');
						case _: lines.push('        cmp = a.${f.name}[idx${f.name}].compareTo(b.${f.name}[idx${f.name}])');
					}
					lines.push('        if (cmp != 0) return cmp');
					lines.push('        idx${f.name} += 1'); lines.push('    }');
					lines.push('    cmp = a.${f.name}.size - b.${f.name}.size');
					lines.push('    if (cmp != 0) return cmp');
					continue;
				default:
			}
			switch(Context.follow(f.type)) {
				case TAbstract(a, _) if(a.get().name == "Int"): lines.push('    cmp = a.${f.name}.compareTo(b.${f.name})');
				case TInst(c, _) if(c.get().name == "String"): lines.push('    cmp = a.${f.name}.compareTo(b.${f.name})');
				case TInst(c, _) if(c.get().meta.has(":dataClass")): imports.requireType(c.get().module, "compare" + c.get().name); lines.push('    cmp = compare${c.get().name}(a.${f.name}, b.${f.name})');
				case TEnum(_, _): lines.push('    cmp = ${cls.name}${f.name}Order(a.${f.name}).compareTo(${cls.name}${f.name}Order(b.${f.name}))');
				case _:
			}
			lines.push('    if (cmp != 0) return cmp');
		}
		lines.push('    return 0');
		lines.push('}');
		return lines.join("\n");
	}

	/** Emits a marked abstract as an inline Kotlin value class. */
	public function valueTypeDecl(cls: ClassType, info: ValueTypeInfo, varFields: Array<ClassVarData>, funcFields: Array<ClassFuncData>): String {
		final abs = info.abstractType;
		final ctor = ValueTypeSupport.constructorField(abs);
		final first = ctor == null ? null : ValueTypeSupport.firstArgument(ctor);
		if(first == null) {
			Context.error("value type constructor must take its representation", cls.pos);
		}
		final fieldName = first.name;
		final representation = types.of(info.representation);
		final lines: Array<String> = ["@JvmInline", "value class " + info.name + "(val " + fieldName + ": " + representation + ") {"];

		if(ctor != null && ValueTypeSupport.constructorThrows(abs)) {
			lines.push("    init {");
			for(line in expr.valueTypeConstructorBody(cls, findFunc(funcFields, "_new"))) lines.push(line);
			lines.push("    }");
		}

		for(f in funcFields) {
			if(f.field.name == "_new" || (ValueTypeSupport.isInlineHelper(f.field) && ValueTypeSupport.operatorOf(abs, f.field) == null)) continue;
			final op = ValueTypeSupport.operatorOf(abs, f.field);
			final isOperator = op != null;
			final receiver = ValueTypeSupport.hasReceiver(f.field);
			final start = isOperator ? (switch(op) { case Binary(_): 1; case Unary(_): f.args.length; }) : (receiver ? 1 : 0);
			final args: Array<String> = [];
			for(i in start...f.args.length) {
				final a = f.args[i];
				final name = isOperator && i == 1 ? "other" : a.name;
				final type = isOperator ? info.name : types.of(a.type);
				args.push(name + (a.opt ? "?" : "") + ": " + type);
			}
			final ret = types.of(f.ret);
			final vis = isOperator || f.field.isPublic ? "" : "private ";
			final name = isOperator ? kotlinOperatorName(op) : f.field.name;
			final overrideKw = f.field.name == "toString" ? "override " : "";
			lines.push("");
			lines.push("    " + vis + overrideKw + (isOperator ? "operator " : "") + "fun " + name + "(" + args.join(", ") + "): " + ret + " {");
			for(line in expr.valueTypeFunctionBody(cls, f, fieldName)) lines.push("    " + line);
			lines.push("    }");
		}

		final staticVars = [for(v in varFields) if(v.isStatic) v];
		if(staticVars.length > 0) {
			lines.push("");
			lines.push("    companion object {");
			for(i in 0...staticVars.length) {
				final v = staticVars[i];
				final initializer = v.field.expr();
				if(initializer == null) Context.error("value type static field must have an initializer", v.field.pos);
				lines.push("        " + (v.field.isPublic ? "" : "private ") + "val " + v.field.name + ": " + info.name + " = " + expr.rawExpression(initializer));
			}
			lines.push("    }");
		}
		lines.push("}");
		return lines.join("\n");
	}

	function findFunc(funcFields: Array<ClassFuncData>, name: String): ClassFuncData {
		for(f in funcFields) if(f.field.name == name) return f;
		Context.error("value type constructor is missing", Context.currentPos());
		return null;
	}

	function kotlinOperatorName(op: ValueTypeOperator): String {
		return switch(op) {
			case Binary(binary): switch(binary) {
				case OpAdd: "plus";
				case OpSub: "minus";
				case OpMult: "times";
				case OpDiv: "div";
				case OpMod: "rem";
				case OpEq: "equals";
				case OpNotEq: "equals";
				case OpLt: "compareTo";
				case OpLte: "compareTo";
				case OpGt: "compareTo";
				case OpGte: "compareTo";
				case _: "plus";
			};
			case Unary(unary): switch(unary) {
				case OpNeg: "unaryMinus";
				case _: "unaryPlus";
			};
		};
	}

	function withExtracted(extractedParts: Array<String>, classPart: String): String {
		return extractedParts.length > 0 ? extractedParts.join("\n\n") + "\n\n" + classPart : classPart;
	}

	/** A haxe.Exception subclass folds, with its payload enum, into a sealed hierarchy. */
	public static function isExceptionSubclass(cls: ClassType): Bool {
		if(cls.superClass == null) {
			return false;
		}
		final parent = cls.superClass.t.get();
		return parent.pack.join(".") == "haxe" && parent.name == "Exception";
	}

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

	function payloadEnumOf(funcFields: Array<ClassFuncData>): Null<EnumType> {
		final ctor = findConstructor(funcFields);
		if(ctor == null) {
			return null;
		}
		for(a in ctor.args) {
			switch(a.type) {
				case TEnum(e, _):
					return e.get();
				case _:
			}
		}
		return null;
	}

	/**
		The message function is the class's static function taking the
		payload enum and returning String; its switch supplies each
		variant's super-call argument.
	**/
	function findMessageFunc(cls: ClassType, funcFields: Array<ClassFuncData>, payload: EnumType): Null<ClassFuncData> {
		var found: Null<ClassFuncData> = null;
		for(f in funcFields) {
			if(!f.isStatic || f.args.length != 1) {
				continue;
			}
			switch(f.args[0].type) {
				case TEnum(e, _):
					if(e.get().module == payload.module) {
						if(found != null) {
							Context.error("exception class carries more than one message function", cls.pos);
							return null;
						}
						found = f;
					}
				case _:
			}
		}
		return found;
	}

	function sealedExceptionDecl(cls: ClassType, payload: EnumType, funcFields: Array<ClassFuncData>): String {
		final options = [for(_ => ef in payload.constructs) ef];
		options.sort((a, b) -> Reflect.compare(a.index, b.index));

		final messageFunc = findMessageFunc(cls, funcFields, payload);
		if(messageFunc == null || messageFunc.expr == null) {
			Context.error("exception class carries no message function for its payload enum", cls.pos);
			return null;
		}
		final messages = new Map<String, String>();
		collectMessageCases(messageFunc.expr, options, messages);

		// The override re-exposes Throwable's nullable message at the
		// non-null String the fold always constructs, so handlers read
		// `error.message` without a null assertion (features/06).
		final lines = [
			'sealed class ${cls.name}(override val message: String) : RuntimeException(message) {'
		];
		for(o in options) {
			final message = messages.get(o.name);
			if(message == null) {
				Context.error("message function misses a case for " + o.name, cls.pos);
				return null;
			}
			final args = enumFieldParams(o);
			if(args.length == 0) {
				lines.push('    data object ${o.name} : ${cls.name}(${message})');
			} else {
				final params = [for(arg in args) 'val ${arg.name}: ${types.of(arg.type)}'].join(", ");
				lines.push('    data class ${o.name}($params) :');
				lines.push('        ${cls.name}(${message})');
			}
		}
		lines.push("}");
		return lines.join("\n");
	}

	/** Constructor argument names and types, read off the enum field's function type. */
	function enumFieldParams(ef: haxe.macro.Type.EnumField): Array<{name: String, type: Type}> {
		return switch(ef.type) {
			case TFun(args, _): [for(a in args) {name: a.name, type: a.t}];
			case _: [];
		};
	}

	/**
		Walks the message function's switch and records, per constructor,
		the rendered super-call argument. Plain string constants stay
		quoted; expressions render through the expression compiler with
		the case's pattern variables in scope.
	**/
	function collectMessageCases(e: TypedExpr, options: Array<haxe.macro.Type.EnumField>, out: Map<String, String>): Void {
		switch(e.expr) {
			case TReturn(r) if(r != null):
				collectMessageCases(r, options, out);
			case TBlock(stmts):
				for(s in stmts) collectMessageCases(s, options, out);
				collectCollapsedCase(stmts, options, out);
			case TMeta(_, inner):
				collectMessageCases(inner, options, out);
			case TSwitch(_, cases, _):
				for(c in cases) {
					if(c.values.length == 0) {
						continue;
					}
					final name = caseConstructorName(c.values[0], options);
					if(name == null) {
						continue;
					}
					bindPatternLocals(c.expr);
					final body = unwrapReturn(c.expr);
					switch(body.expr) {
						case TConst(TString(s)):
							out.set(name, '"' + s + '"');
						case _:
							out.set(name, expr.rawExpression(body));
					}
				}
			case _:
		}
	}

	/**
		Renames a case body's pattern captures to the payload argument
		names of their constructors, following plain local aliases. The
		typer hands captures over as generated temporaries; the emitted
		variant exposes the payload as its constructor property, whose
		name is the declaration's argument name.
	**/
	/**
		A single-case switch never survives typing: it arrives as a block
		holding the pattern capture and the case body, so the TSwitch walk
		in collectMessageCases cannot see it. Recover the constructor from
		the capture's payload extraction and the message from the trailing
		return.
	**/
	function collectCollapsedCase(stmts: Array<TypedExpr>, options: Array<haxe.macro.Type.EnumField>, out: Map<String, String>): Void {
		if(stmts.length != 2) {
			return;
		}
		switch(stmts[0].expr) {
			case TVar(_, init) if(init != null):
				switch(stripDecorations(init).expr) {
					case TEnumParameter(_, ef, _):
						final name = ef.name;
						for(o in options) {
							if(o.name != name) {
								continue;
							}
							bindPatternLocals(stmts[0]);
							bindPatternLocals(stmts[1]);
							final body = unwrapReturn(stmts[1]);
							switch(body.expr) {
								case TConst(TString(s)):
									out.set(name, '"' + s + '"');
								case _:
									out.set(name, expr.rawExpression(body));
							}
						}
					case _:
				}
			case _:
		}
	}

	function bindPatternLocals(e: TypedExpr): Void {
		switch(e.expr) {
			case TBlock(stmts):
				for(s in stmts) bindPatternLocals(s);
			case TVar(v, init) if(init != null):
				switch(stripDecorations(init).expr) {
					case TEnumParameter(_, ef, index):
						expr.bindLocalName(v, expr.payloadName(ef, index));
					case TLocal(source):
						final bound = expr.boundNameOf(source);
						if(bound != null) {
							expr.bindLocalName(v, bound);
						}
					case _:
				}
			case _:
		}
	}

	function stripDecorations(e: TypedExpr): TypedExpr {
		return switch(e.expr) {
			case TParenthesis(inner) | TCast(inner, _) | TMeta(_, inner): stripDecorations(inner);
			case _: e;
		}
	}

	function caseConstructorName(value: TypedExpr, options: Array<haxe.macro.Type.EnumField>): Null<String> {
		switch(value.expr) {
			// Enum switches lower to a switch on the constructor index;
			// the payload enum's own constructs carry the index mapping.
			case TConst(TInt(index)):
				for(o in options) {
					if(o.index == index) {
						return o.name;
					}
				}
				return null;
			case TField(_, FEnum(_, ef)):
				return ef.name;
			case TEnumParameter(_, ef, _):
				return ef.name;
			case _:
				return null;
		}
	}

	function unwrapReturn(e: TypedExpr): TypedExpr {
		return switch(e.expr) {
			case TReturn(r) if(r != null): unwrapReturn(r);
			case TBlock(stmts) if(stmts.length > 0):
				// Leading pattern-variable bindings drop out: inside the
				// emitted variant the payload name is the constructor
				// property, so the rendered body refers to it directly.
				unwrapReturn(stmts[stmts.length - 1]);
			case _: e;
		}
	}

	function isAllStatic(varFields: Array<ClassVarData>, funcFields: Array<ClassFuncData>): Bool {
		for(v in varFields) {
			if(!v.isStatic) return false;
		}
		for(f in funcFields) {
			if(f.field.name == "new") return false;
			if(!f.isStatic) return false;
		}
		return true;
	}

	function findConstructor(funcFields: Array<ClassFuncData>): Null<ClassFuncData> {
		for(f in funcFields) {
			if(f.field.name == "new") return f;
		}
		return null;
	}

	/**
		The names of a function's own type parameters, in first-use order
		over the signature. A generic method references its parameters as
		type-parameter classes; the enclosing class owns its parameters
		in the class header.
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

	function buildPrimaryConstructor(cls: ClassType, ctor: ClassFuncData, varFields: Array<ClassVarData>): String {
		if(ctor.args.length == 0) return "";
		final params: Array<String> = [];
		for(a in ctor.args) {
			var isField = false;
			var isFinal = true;
			var isPublic = false;
			for(v in varFields) {
				if(v.field.name == a.name) {
					isField = true;
					isFinal = v.field.isFinal;
					isPublic = v.field.isPublic;
					break;
				}
			}
			// A constructor-parameter field keeps its declared visibility in
			// the primary constructor (feature spec 27); a parameter without
			// a same-named field stays a plain parameter.
			final prefix = isField ? (isPublic ? "" : "private ") + (isFinal ? "val " : "var ") : "";
			final coalescing = DefaultArgExpander.coalescingDefaultAt(cls, ctor.field.name, a.index);
			final parameterType = coalescing != null ? DefaultArgExpander.coalescingParameterType(coalescing, a.type) : a.type;
			final defaultText = coalescing != null ? " = " + expr.coalescingDefaultText(coalescing, a.type) : "";
			params.push(prefix + a.name + ": " + types.of(parameterType) + defaultText);
		}
		return "(" + params.join(", ") + ")";
	}

	/**
		The surviving init-block lines wrapped as one init block, the first
		class member (feature spec 27). A constructor with nothing left to
		render emits nothing.
	**/
	function ctorInitBlock(body: Array<String>): Array<String> {
		if(body.length == 0) {
			return [];
		}
		return ["    init {"].concat(body).concat(["    }"]);
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
		The synthesized record print is dropped only while the Kotlin data
		class native print produces the same text. The native print follows
		the primary constructor's parameter order, and the synthesized print
		follows field declaration order (feature spec 37 rule 3); a class
		whose two orders differ keeps the member as an explicit override.
	**/
	static function isSynthesizedRecordToString(cls: ClassType, f: ClassFuncData): Bool {
		if(!(cls.meta.has(":dataClass") && f.field.name == "toString" && f.field.meta.has(":recordMember"))) {
			return false;
		}
		return constructorOrderMatchesFieldOrder(cls);
	}

	/**
		Compares the constructor parameter order with the declaration order
		of the fields holding the parameters, the same position comparison
		the stage 1 shape applies. A parameter without a field fails the
		dataClass validation in classDecl; the native print stays until
		that error fires.
	**/
	static function constructorOrderMatchesFieldOrder(cls: ClassType): Bool {
		final ctor = cls.constructor;
		if(ctor == null) {
			return true;
		}
		final args = switch(ctor.get().type) {
			case TFun(args, _): args;
			case _: return true;
		};
		final positions = new Map<String, Int>();
		for(field in cls.fields.get()) {
			positions.set(field.name, Context.getPosInfos(field.pos).min);
		}
		var last = -1;
		for(arg in args) {
			final position = positions.get(arg.name);
			if(position == null) {
				return true;
			}
			if(position < last) {
				return false;
			}
			last = position;
		}
		return true;
	}

	function objectVarDecl(v: ClassVarData, cls: ClassType): Array<String> {
		final field = v.field;
		if(v.isStatic && isFunctionType(field.type)) {
			return staticFunctionVarDecl(v);
		}
		if(v.isStatic && DataTableHelper.isDataTableField(field)) {
			final elems = DataTableHelper.getDataTableElements(field.expr());
			if(elems != null) {
				final formatted = [for(x in elems) (x >= 0 && x <= 9) ? Std.string(x) : "0x" + StringTools.hex(x).toLowerCase()];
				final chunks: Array<String> = [];
				var i = 0;
				while(i < formatted.length) {
					final end = Std.int(Math.min(i + 8, formatted.length));
					chunks.push("        " + formatted.slice(i, end).join(", "));
					i = end;
				}
				// A resident table crosses into ReadOnlyArray parameters
				// (List<T> here), so it renders as a list; business
				// tables stay primitive arrays because business code
				// indexes them directly and never passes them along.
				final wrapper = imports.selfResident ? "listOf" : "intArrayOf";
				return [
					'    val ${field.name} = $wrapper(\n' + chunks.join(",\n") + '\n    )'
				];
			}
		}
		if(v.isStatic) {
			final init = StaticFieldHelper.validatedInitializer(field, cls);
			final initStr = StaticFieldHelper.isNonEmptyArrayLiteral(init) && StaticFieldHelper.isReadOnlyArrayType(field.type)
				? expr.rawArrayExpression(init, "listOf")
				: expr.rawExpression(init);
			final kw = field.isFinal && StaticFieldHelper.isConstValue(field) ? "const val" : (field.isFinal ? "val" : "var");
			final vis = field.isPublic ? "" : "private ";
			final jvmField = !field.isFinal ? ["    @JvmField"] : [];
			return jvmField.concat(['    $vis$kw ${field.name}: ${types.of(field.type)} = $initStr']);
		}
		if(field.meta.has(":value")) {
			Context.error("instance field default has no lowering; assign it in the constructor", field.pos);
		}
		return ['    val ${field.name}: ${types.of(field.type)}'];
	}

	function staticFunctionVarDecl(v: ClassVarData): Array<String> {
		final field = v.field;
		final initializer = field.expr();
		if(initializer == null) {
			Context.error("static function fields require initializers", field.pos);
			return [];
		}
		return ['    val ${field.name}: ${types.of(field.type)} = ${expr.rawExpression(initializer)}'];
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

	function classVarDecl(v: ClassVarData): Array<String> {
		final field = v.field;
		final kw = field.isFinal ? "val" : "var";
		final vis = field.isPublic ? "" : "private ";
		var initStr = "";
		switch(field.kind) {
			case FVar(_, _):
				// Uninitialized fields carry the platform default: numeric
				// types zero, buffer types a fresh empty instance.
				switch(field.type) {
					case TAbstract(a, _) if(a.get().name == "Int"):
						initStr = " = 0";
					case TInst(c, _) if(isModuleType(c.get(), "haxe.io", "BytesBuffer")):
						imports.requireType(c.get().module, "BytesBuffer");
						initStr = " = BytesBuffer()";
					case _:
				}
			case _:
		}
		return ['    ${vis}${kw} ${field.name}: ${types.of(field.type)}$initStr'];
	}

	function isModuleType(cls: ClassType, packDot: String, name: String): Bool {
		return cls.pack.join(".") == packDot && cls.name == name;
	}

	function isInterfaceMethod(cls: ClassType, f: ClassFuncData): Bool {
		for(iface in cls.interfaces) {
			final ifaceCls = iface.t.get();
			for(field in ifaceCls.fields.get()) {
				if(field.name == f.field.name) return true;
			}
		}
		return false;
	}

	function funcDecl(cls: ClassType, f: ClassFuncData, isObject: Bool): Array<String> {
		for(a in f.args) {
			expr.reserveName(a.name);
		}
		final args = [for(a in f.args) {
			final coalescing = DefaultArgExpander.coalescingDefaultAt(cls, f.field.name, a.index);
			final parameterType = coalescing != null ? DefaultArgExpander.coalescingParameterType(coalescing, a.type) : a.type;
			final defaultText = coalescing != null ? " = " + expr.coalescingDefaultText(coalescing, a.type) : "";
			'${a.name}: ${types.of(parameterType)}$defaultText';
		}].join(", ");
		final retType = types.of(f.ret);
		final ret = retType == "Unit" ? "" : ": " + retType;
		final vis = f.field.isPublic ? "" : "private ";
		// A zero-argument toString overrides kotlin.Any's member; the
		// modifier is required even though Haxe models no Any root, so
		// no superclass link exists to derive it from (feature spec 27).
		final overridesAny = f.field.name == "toString" && f.args.length == 0;
		final overrideStr = (isInterfaceMethod(cls, f) || overridesAny) ? "override " : "";
		// A method's own type parameters (the resident builders'
		// factory functions) render as method generics; the class's own
		// parameters stay in the class header only.
		final methodParams = collectMethodTypeParams(cls, f);
		final genericStr = methodParams.length > 0 ? "<" + methodParams.join(", ") + "> " : "";
		final head = '    ${vis}${overrideStr}fun ${genericStr}${f.field.name}($args)$ret {';

		final boundary = switch(f.ret) {
			case TAbstract(a, _):
				final abs = a.get();
				abs.pack.join(".") == "std" && abs.name == "ReadOnlyArray";
			case _: false;
		};
		expr.setDecodeBoundary(boundary);
		final body = expr.functionBody(cls, f);
		expr.setDecodeBoundary(false);

		return [head].concat(body.map(l -> "    " + l)).concat(["    }"]);
	}

	function extractedFuncDecl(cls: ClassType, f: ClassFuncData): Array<String> {
		for(a in f.args) {
			expr.reserveName(a.name);
		}
		final isExtension = StaticFunctionMarkers.isExtension(f.field);
		final firstArg = isExtension ? 1 : 0;
		final args = [for(i in firstArg...f.args.length) {
			final a = f.args[i];
			final coalescing = DefaultArgExpander.coalescingDefaultAt(cls, f.field.name, a.index);
			final parameterType = coalescing != null ? DefaultArgExpander.coalescingParameterType(coalescing, a.type) : a.type;
			final defaultText = coalescing != null ? " = " + expr.coalescingDefaultText(coalescing, a.type) : "";
			'${a.name}: ${types.of(parameterType)}$defaultText';
		}].join(", ");
		final retType = types.of(f.ret);
		final ret = retType == "Unit" ? "" : ": " + retType;
		final vis = f.field.isPublic ? "" : "private ";
		final methodParams = collectMethodTypeParams(cls, f);
		final genericStr = methodParams.length > 0 ? "<" + methodParams.join(", ") + "> " : "";
		final receiver = isExtension ? types.of(f.args[0].type) + "." : "";
		final head = '${vis}fun ${genericStr}${receiver}${f.field.name}($args)$ret {';
		if(isExtension && f.args[0].tvar != null) {
			expr.bindLocalName(f.args[0].tvar, "this");
		}
		final boundary = switch(f.ret) {
			case TAbstract(a, _):
				final abs = a.get();
				abs.pack.join(".") == "std" && abs.name == "ReadOnlyArray";
			case _: false;
		};
		expr.setDecodeBoundary(boundary);
		final body = expr.functionBody(cls, f);
		expr.setDecodeBoundary(false);
		return [head].concat(body).concat(["}"]);
	}

	public function testFuncDecl(cls: ClassType, f: ClassFuncData): Array<String> {
		final id = cls.module + "." + f.field.name;
		var desc: Null<String> = null;
		for(entry in f.field.meta.extract(":test")) {
			if(entry.params != null && entry.params.length > 0) {
				switch(entry.params[0].expr) {
					case EConst(CString(s)): desc = s;
					case _:
				}
			}
		}
		final runnerName = desc != null ? id + ": " + desc : id;
		final runtimePackage = RuntimeConfig.requireImportName("test module " + cls.module);
		imports.require(runtimePackage + ".test.Test");
		final body = expr.functionBody(cls, f);
		final indented = body.map(l -> "            " + l);
		return [
			"    @kotlin.test.Test",
			'    fun ${f.field.name}() {',
			'        Test.run("${escapeKotlinString(id)}", "${escapeKotlinString(runnerName)}") {',
		].concat(indented).concat([
			"        }",
			"    }"
		]);
	}

	static function escapeKotlinString(s: String): String {
		final out = new StringBuf();
		for(i in 0...s.length) {
			final c = s.charAt(i);
			if(c == '"') out.add('\\"');
			else if(c == "\\") out.add("\\\\");
			else if(c == "\n") out.add("\\n");
			else if(c == "\r") out.add("\\r");
			else if(c == "\t") out.add("\\t");
			else if(c == "$") out.add("\\$");
			else out.add(c);
		}
		return out.toString();
	}

	// ------------------------------------------------------------------
	// Enums (stdlib/03)
	// ------------------------------------------------------------------

	public function enumDecl(en: EnumType, options: Array<EnumOptionData>): String {
		final sorted = options.copy();
		sorted.sort((a, b) -> Reflect.compare(a.field.index, b.field.index));
		var valueEnum = true;
		for(o in sorted) if(o.args.length > 0) valueEnum = false;
		if(valueEnum) {
			return 'enum class ${en.name} {\n    ' + [for(o in sorted) o.name].join(",\n    ") + '\n}';
		}
		final lines = ['sealed interface ${en.name} {'];
		for(o in sorted) {
			if(o.args.length == 0) {
				lines.push('    data object ${o.name} : ${en.name}');
			} else {
				final params = [for(arg in o.args) 'val ${arg.name}: ${types.of(arg.type)}'].join(", ");
				lines.push('    data class ${o.name}($params) : ${en.name}');
			}
		}
		lines.push("}");
		return lines.join("\n");
	}

	// ------------------------------------------------------------------
	// Typedefs (features/03, features/18)
	// ------------------------------------------------------------------

	public function typedefDecl(def: DefType): String {
		switch(def.type) {
			case TAnonymous(anonRef):
				final fields = anonRef.get().fields.copy();
				fields.sort((a, b) -> Reflect.compare(Context.getPosInfos(a.pos).min, Context.getPosInfos(b.pos).min));
				final fieldLines = [for(field in fields) '    val ${field.name}: ${types.of(field.type)}'];
				final dataClassStr = ['data class ${def.name}(', fieldLines.join(",\n"), ')'].join("\n");

				if(isStructKeyCandidate(fields)) {
					final cmpLines = [
						'fun compare(a: ${def.name}, b: ${def.name}): Int {',
						'    if (a === b) return 0',
						'    var cmp = 0'
					];
					for(f in fields) {
						switch(Context.follow(f.type)) {
							case TAbstract(a, _) if(a.get().name == "Int" || a.get().name == "Bool"):
								cmpLines.push('    cmp = a.${f.name}.compareTo(b.${f.name})');
								cmpLines.push('    if (cmp != 0) return cmp');
							case TInst(c, _) if(c.get().name == "String"):
								cmpLines.push('    cmp = a.${f.name}.compareTo(b.${f.name})');
								cmpLines.push('    if (cmp != 0) return cmp');
							case _:
								switch(f.type) {
									case TType(innerDef, _):
										imports.requireType(innerDef.get().module, "compare");
										cmpLines.push('    cmp = compare(a.${f.name}, b.${f.name})');
										cmpLines.push('    if (cmp != 0) return cmp');
									case _:
								}
						}
					}
					cmpLines.push('    return 0');
					cmpLines.push('}');
					return dataClassStr + "\n\n" + cmpLines.join("\n");
				}

				return dataClassStr;
			case TType(_, _):
				// An alias typedef lowers to a platform alias of the
				// underlying named type.
				return 'typealias ${def.name} = ${types.of(def.type)}';
			case _:
				return null;
		}
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
