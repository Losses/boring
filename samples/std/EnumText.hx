package std;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.ExprTools;
import haxe.macro.Type;
import haxe.macro.TypeTools;

/**
 * Stage 1 labeled constructor forms for payload enum operands
 * (docs/specs/features/40-sorted-table-fields-and-stage1-enum-forms.md
 * ruling 4). Every entry point runs only when the compilation defines
 * `boring_oracle`, the stage 1 reference build. The five generated
 * targets keep the Std.string interception of feature spec 34, so the
 * source text of every operand site stays unchanged.
 */
class EnumText {
	/**
	 * Whether the enum declares at least one constructor that carries
	 * arguments. Parameterless enums print their constructor names
	 * natively on every compilation and need no generated branch.
	 */
	public static function hasPayloadConstructor(e:EnumType):Bool {
		for(ctor in e.constructs) {
			switch(ctor.type) {
				case TFun(args, _) if(args.length > 0):
					return true;
				case _:
			}
		}
		return false;
	}

	/**
	 * The stage 1 operand for one payload enum value: an immediately
	 * invoked local function whose body returns the exhaustive labeled
	 * switch. An argument of the same enum type recurses through the
	 * function name. The recursive constructor renders at run time. The switch is
	 * not expanded again at macro time. An argument of
	 * a different payload enum type gets its own renderer call here.
	 */
	public static function rendererCall(value:Expr, valueType:Type, e:EnumType, pos:Position):Expr {
		final written = TypeTools.toComplexType(valueType);
		final param = {expr: EConst(CIdent("enumTextValue")), pos: pos};
		final body = labeledForm(param, e, pos, "enumTextRender", e);
		return {
			expr: ECall({
				expr: EFunction(FNamed("enumTextRender", null), {
					args: [{name: "enumTextValue", type: written, opt: false, value: null}],
					ret: (macro :String),
					expr: {expr: EBlock([{expr: EReturn(body), pos: pos}]), pos: pos}
				}),
				pos: pos
			}, [value]),
			pos: pos
		};
	}

	/**
	 * The exhaustive labeled switch over every constructor in declaration
	 * order, with no default arm. A parameterless constructor prints its
	 * bare name; a constructor with arguments prints
	 * `Name(param=form, ...)` with the argument forms of feature spec 34
	 * ruling 3. `selfName` names the enclosing renderer function and
	 * `root` its enum type; an operand of that type calls the function.
	 */
	static function labeledForm(value:Expr, e:EnumType, pos:Position, selfName:Null<String>, root:EnumType):Expr {
		final cases:Array<Case> = [];
		for(ctor in e.constructs) {
			final args = switch(ctor.type) {
				case TFun(args, _): args;
				case _: [];
			};
			final pattern:Expr = args.length == 0
				? {expr: EConst(CIdent(ctor.name)), pos: pos}
				: {
					expr: ECall({expr: EConst(CIdent(ctor.name)), pos: pos}, [for(arg in args) {expr: EConst(CIdent(arg.name)), pos: pos}]),
					pos: pos
				};
			cases.push({values: [pattern], guard: null, expr: constructorText(ctor.name, args, pos, selfName, root)});
		}
		return {expr: ESwitch(value, cases, null), pos: pos};
	}

	/**
	 * Rewrites `Std.string(x)` calls whose argument identifier is bound,
	 * through a written parameter or local type, to a payload enum: the
	 * call becomes the labeled switch. The rewrite runs in the build
	 * macro pass before typing, so it never reaches the generated
	 * targets and the call site source stays unchanged.
	 */
	public static function rewriteStringCalls(fields:Array<Field>):Void {
		for(field in fields) {
			final fun = switch(field.kind) {
				case FFun(fun): fun;
				case _: null;
			};
			if(fun == null || fun.expr == null) {
				continue;
			}
			final scopes:Array<Map<String, Type>> = [new Map<String, Type>()];
			for(arg in fun.args) {
				final resolved = resolveWrittenType(arg.type, fun.expr.pos);
				if(resolved != null) {
					scopes[0].set(arg.name, resolved);
				}
			}
			rewrite(fun.expr, scopes);
		}
	}

	static function rewrite(e:Expr, scopes:Array<Map<String, Type>>):Void {
		if(e == null) {
			return;
		}
		switch(e.expr) {
			case ECall(callee, args) if(isStdStringCallee(callee) && args.length == 1):
				switch(args[0].expr) {
					case EConst(CIdent(name)):
						final bound = lookup(scopes, name);
						if(bound != null) {
							final followed = Context.follow(bound);
							switch(followed) {
								case TEnum(en, _):
									final enumType = en.get();
									if(hasPayloadConstructor(enumType)) {
										e.expr = rendererCall(args[0], followed, enumType, e.pos).expr;
										return;
									}
								case _:
							}
						}
					case _:
				}
			case _:
		}
		switch(e.expr) {
			case EBlock(exprs):
				scopes.push(new Map<String, Type>());
				for(child in exprs) {
					rewrite(child, scopes);
				}
				scopes.pop();
			case EFunction(_, fun):
				final scope = new Map<String, Type>();
				for(arg in fun.args) {
					final resolved = resolveWrittenType(arg.type, e.pos);
					if(resolved != null) {
						scope.set(arg.name, resolved);
					}
				}
				scopes.push(scope);
				rewrite(fun.expr, scopes);
				scopes.pop();
			case EVars(vars):
				for(variable in vars) {
					rewrite(variable.expr, scopes);
					final resolved = resolveWrittenType(variable.type, e.pos);
					if(resolved != null) {
						scopes[scopes.length - 1].set(variable.name, resolved);
					}
				}
			case _:
				ExprTools.iter(e, (child:Expr) -> rewrite(child, scopes));
		}
	}

	static function isStdStringCallee(callee:Expr):Bool {
		return switch(callee.expr) {
			case EField({expr: EConst(CIdent("Std"))}, "string"): true;
			case _: false;
		};
	}

	/**
	 * A written type resolves to a binding only when the build context
	 * can type it standalone. A method type parameter does not resolve
	 * outside its generic body, and such an argument never names a
	 * payload enum, so the walker skips it.
	 */
	static function resolveWrittenType(written:Null<ComplexType>, pos:Position):Null<Type> {
		if(written == null) {
			return null;
		}
		return try {
			Context.resolveType(written, pos);
		} catch(error:Dynamic) {
			null;
		};
	}

	static function lookup(scopes:Array<Map<String, Type>>, name:String):Null<Type> {
		var index = scopes.length - 1;
		while(index >= 0) {
			final found = scopes[index].get(name);
			if(found != null) {
				return found;
			}
			index -= 1;
		}
		return null;
	}

	static function constructorText(name:String, args:Array<{name:String, opt:Bool, t:Type}>, pos:Position, selfName:Null<String>, root:EnumType):Expr {
		if(args.length == 0) {
			return {expr: EConst(CString(name)), pos: pos};
		}
		final parts:Array<Expr> = [{expr: EConst(CString(name + "(")), pos: pos}];
		for(index in 0...args.length) {
			if(index > 0) {
				parts.push({expr: EConst(CString(", ")), pos: pos});
			}
			parts.push({expr: EConst(CString(args[index].name + "=")), pos: pos});
			parts.push(operandForm(args[index].t, {expr: EConst(CIdent(args[index].name)), pos: pos}, pos, selfName, root));
		}
		parts.push({expr: EConst(CString(")")), pos: pos});
		return concat(parts, pos);
	}

	/**
	 * The stage 1 operand form of one constructor argument (feature spec
	 * 34 ruling 3): a payload enum argument of the renderer's own enum
	 * calls the renderer function, a payload enum argument of another
	 * enum gets its own renderer call, a record argument prints through
	 * its member, an array argument joins its elements with `", "` through
	 * an index loop, and every other argument reads through Std.string. A
	 * nullable enum argument has no ruled form and reads through
	 * Std.string.
	 */
	static function operandForm(type:Type, read:Expr, pos:Position, selfName:Null<String>, root:Null<EnumType>):Expr {
		switch(type) {
			case TAbstract(a, _) if(a.get().name == "Null"):
				return stdString(read, pos);
			case _:
		}
		switch(Context.follow(type)) {
			case TEnum(en, params):
				final enumType = en.get();
				if(!hasPayloadConstructor(enumType)) {
					return stdString(read, pos);
				}
				if(selfName != null && root != null && sameEnum(enumType, root)) {
					return {expr: ECall({expr: EConst(CIdent(selfName)), pos: pos}, [read]), pos: pos};
				}
				return rendererCall(read, TEnum(en, params), enumType, pos);
			case TInst(c, params):
				final cls = c.get();
				if(cls.meta.has(":dataClass")) {
					return {expr: ECall({expr: EField(read, "toString"), pos: pos}, []), pos: pos};
				}
				if(cls.name == "Array" && params.length == 1) {
					return arrayForm(params[0], read, pos, selfName, root);
				}
				return stdString(read, pos);
			case _:
				return stdString(read, pos);
		}
	}

	/**
	 * Whether two enum descriptors name the same declared enum, through
	 * module path and name.
	 */
	static function sameEnum(a:EnumType, b:EnumType):Bool {
		return a.module == b.module && a.name == b.name;
	}

	public static function arrayForm(elementType:Type, read:Expr, pos:Position, selfName:Null<String>, root:Null<EnumType>):Expr {
		final elemWritten = TypeTools.toComplexType(elementType);
		final arrayWritten:Null<ComplexType> = elemWritten == null ? null : (macro :Array<$elemWritten>);
		return arrayFormWithType(elementType, read, pos, selfName, root, arrayWritten);
	}

	public static function stage1ArrayForm(elementType:Type, read:Expr, pos:Position, selfName:Null<String>, root:Null<EnumType>, arrayType:Type):Expr {
		return arrayFormWithType(elementType, read, pos, selfName, root, TypeTools.toComplexType(arrayType));
	}

	static function arrayFormWithType(elementType:Type, read:Expr, pos:Position, selfName:Null<String>, root:Null<EnumType>, arrayWrittenType:Null<ComplexType>):Expr {
		final arrayIdent = {expr: EConst(CIdent("enumTextArray")), pos: pos};
		final out = {expr: EConst(CIdent("enumTextOut")), pos: pos};
		final index = {expr: EConst(CIdent("enumTextIndex")), pos: pos};
		// The element form sits in a named function declared before the loop
		// so the loop body carries calls only. A renderer or nested array
		// form written inline would leave a function value inside the loop
		// body, which rule V08 of the style standard rejects.
		final elemIdent = {expr: EConst(CIdent("enumTextElem")), pos: pos};
		final elementWritten = TypeTools.toComplexType(elementType);
		final elementFunction:Expr = {
			expr: EFunction(FNamed("enumTextElement", null), {
				args: [{name: "enumTextElem", type: elementWritten, opt: false, value: null}],
				ret: (macro :String),
				expr: {expr: EBlock([{expr: EReturn(operandForm(elementType, elemIdent, pos, selfName, root)), pos: pos}]), pos: pos}
			}),
			pos: pos
		};
		final elementCall:Expr = {
			expr: ECall({expr: EConst(CIdent("enumTextElement")), pos: pos}, [{expr: EArray(arrayIdent, index), pos: pos}]),
			pos: pos
		};
		final body:Expr = {
			expr: EBlock([
				{
					expr: EVars([{
						name: "enumTextOut",
						type: (macro :StringBuf),
						expr: {expr: ENew({pack: [], name: "StringBuf", sub: null, params: []}, []), pos: pos},
						isFinal: true
					}]),
					pos: pos
				},
				elementFunction,
				{
					expr: ECall({expr: EField(out, "add"), pos: pos}, [{expr: EConst(CString("[")), pos: pos}]),
					pos: pos
				},
				{
					expr: EFor(
						{
							expr: EBinop(
								OpIn,
								index,
								{expr: EBinop(OpInterval, {expr: EConst(CInt("0")), pos: pos}, {expr: EField(arrayIdent, "length"), pos: pos}), pos: pos}
							),
							pos: pos
						},
						{
							expr: EBlock([
								{
									expr: EIf(
										{expr: EBinop(OpGt, index, {expr: EConst(CInt("0")), pos: pos}), pos: pos},
										{expr: ECall({expr: EField(out, "add"), pos: pos}, [{expr: EConst(CString(", ")), pos: pos}]), pos: pos},
										null
									),
									pos: pos
								},
								{
									expr: ECall({expr: EField(out, "add"), pos: pos}, [elementCall]),
									pos: pos
								}
							]),
							pos: pos
						}
					),
					pos: pos
				},
				{
					expr: ECall({expr: EField(out, "add"), pos: pos}, [{expr: EConst(CString("]")), pos: pos}]),
					pos: pos
				},
				{
					expr: EReturn({expr: ECall({expr: EField(out, "toString"), pos: pos}, []), pos: pos}),
					pos: pos
				}
			]),
			pos: pos
		};
		final arrayWritten = arrayWrittenType;
		return {
			expr: ECall({
				expr: EFunction(FAnonymous, {
					args: [{name: "enumTextArray", type: arrayWritten, opt: false, value: null}],
					ret: (macro :String),
					expr: body
				}),
				pos: pos
			}, [read]),
			pos: pos
		};
	}

	static function stdString(read:Expr, pos:Position):Expr {
		return {expr: ECall({expr: EField({expr: EConst(CIdent("Std")), pos: pos}, "string"), pos: pos}, [read]), pos: pos};
	}

	static function concat(parts:Array<Expr>, pos:Position):Expr {
		var out = parts[0];
		for(index in 1...parts.length) {
			out = {expr: EBinop(OpAdd, out, parts[index]), pos: pos};
		}
		return out;
	}
}
#end
