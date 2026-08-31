package std;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

typedef RecordShapeData = {
	var names:Array<String>;
	var fieldTypes:Array<Type>;
	var isClass:Bool;
	var name:String;
}
#end

/**
 * The field list of a record receiver, shared by the record macros
 * (docs/specs/features/27-class-members-and-records.md). Class records
 * yield the fields held by constructor parameters, in constructor
 * parameter order; anonymous records yield all fields in declaration
 * order. A receiver that is neither stops the compilation.
 */
class RecordShape {
	#if macro
	public static function of(receiver:Expr, message:String):RecordShapeData {
		final type = try {
			Context.typeof(receiver);
		} catch (e:Dynamic) {
			Context.fatalError(message, receiver.pos);
		}
		switch(Context.follow(type)) {
			case TAnonymous(a):
				return anonymousShape(a.get());
			case TInst(c, _):
				final cls = c.get();
				if(!cls.meta.has(":dataClass")) {
					Context.fatalError(message, receiver.pos);
				}
				return classShape(cls, receiver.pos,
					"record operations require at least one constructor parameter",
					"record copy requires every constructor parameter to be a class field");
			default:
				return Context.fatalError(message, receiver.pos);
		}
	}

	/**
	 * Returns the class being processed by a build macro. The member macro
	 * uses the marker-specific validation text from feature spec 27.
	 */
	public static function local(fields:Array<Field>):RecordShapeData {
		final localClass = Context.getLocalClass();
		if(localClass == null) {
			return Context.fatalError("record member synthesis requires a local class", Context.currentPos());
		}
		final cls = localClass.get();
		if(!cls.meta.has(":dataClass")) {
			return Context.fatalError("record member synthesis requires @:dataClass", cls.pos);
		}

		var constructorArgs:Null<Array<FunctionArg>> = null;
		for(field in fields) {
			if(field.name != "new") {
				continue;
			}
			switch(field.kind) {
				case FFun(fun):
					constructorArgs = fun.args;
				case _:
			}
		}
		if(constructorArgs == null || constructorArgs.length == 0) {
			return Context.fatalError("@:dataClass requires at least one constructor parameter", cls.pos);
		}

		final typedFieldTypes = new Map<String, Type>();
		for(field in fields) {
			final complexType:Null<ComplexType> = switch(field.kind) {
				case FVar(type, _): type;
				case FProp(_, _, type, _): type;
				case _: null;
			};
			if(complexType != null) {
				typedFieldTypes.set(field.name, Context.resolveType(complexType, field.pos));
			}
		}

		final classFields = new Map<String, ClassField>();
		for(field in cls.fields.get()) {
			classFields.set(field.name, field);
		}
		final names:Array<String> = [];
		final fieldTypes:Array<Type> = [];
		for(arg in constructorArgs) {
			if(!typedFieldTypes.exists(arg.name) && !classFields.exists(arg.name)) {
				return Context.fatalError("@:dataClass requires every constructor parameter to be a class field", cls.pos);
			}
			names.push(arg.name);
			final fieldType = typedFieldTypes.get(arg.name);
			fieldTypes.push(fieldType != null ? fieldType : classFields.get(arg.name).type);
		}
		return {names: names, fieldTypes: fieldTypes, isClass: true, name: cls.name};
	}

	/**
	 * Builds the printed form for both the call-site macro and a synthesized
	 * member. Record-typed fields call their own member explicitly so each
	 * target uses the nested record's printed form.
	 */
	public static function assemble(receiver:Expr, shape:RecordShapeData):Expr {
		final open = shape.isClass ? shape.name + "(" : "{ ";
		final close = shape.isClass ? ")" : " }";
		var out:Expr = {expr: EConst(CString(open)), pos: receiver.pos};
		for(i in 0...shape.names.length) {
			final name = shape.names[i];
			if(i > 0) {
				out = {expr: EBinop(OpAdd, out, {expr: EConst(CString(", ")), pos: receiver.pos}), pos: receiver.pos};
			}
			out = {expr: EBinop(OpAdd, out, {expr: EConst(CString(name + "=")), pos: receiver.pos}), pos: receiver.pos};
			final read:Expr = {expr: EField(receiver, name), pos: receiver.pos};
			final fieldType = shape.fieldTypes[i];
			final value = isRecordType(fieldType)
				? (isNullableType(fieldType) ? nullableRecordFieldValue(read, receiver.pos) : memberCallValue(read, receiver.pos))
				: read;
			out = {expr: EBinop(OpAdd, out, value), pos: receiver.pos};
		}
		return {expr: EBinop(OpAdd, out, {expr: EConst(CString(close)), pos: receiver.pos}), pos: receiver.pos};
	}

	/**
	 * The printed operand for one record-typed field. The field's own
	 * member supplies the text (feature spec 31); a nullable field wraps
	 * the call in an explicit null comparison.
	 */
	static function memberCallValue(read:Expr, pos:Position):Expr {
		return {expr: ECall({expr: EField(read, "toString"), pos: pos}, []), pos: pos};
	}

	/**
	 * The printed operand for one nullable record-typed field. A null
	 * field prints "null" and a present field prints the field's own
	 * member text, the same two states the Kotlin data class synthesis
	 * prints. Non-nullable record fields read through the plain member
	 * call; Swift and Rust have no valid nil or None comparison for a
	 * non-optional operand.
	 */
	static function nullableRecordFieldValue(read:Expr, pos:Position):Expr {
		final nullLiteral = {expr: EConst(CIdent("null")), pos: pos};
		final isNull = {expr: EBinop(OpEq, read, nullLiteral), pos: pos};
		return {expr: ETernary(isNull, {expr: EConst(CString("null")), pos: pos}, memberCallValue(read, pos)), pos: pos};
	}

	static function isNullableType(type:Type):Bool {
		return switch(type) {
			case TAbstract(a, _): a.get().name == "Null";
			case _: false;
		};
	}

	static function anonymousShape(anon:AnonType):RecordShapeData {
		final fields = anon.fields.copy();
		for(i in 0...fields.length) {
			for(j in (i + 1)...fields.length) {
				if(Context.getPosInfos(fields[i].pos).min > Context.getPosInfos(fields[j].pos).min) {
					final tmp = fields[i];
					fields[i] = fields[j];
					fields[j] = tmp;
				}
			}
		}
		return {
			names: [for(field in fields) field.name],
			fieldTypes: [for(field in fields) field.type],
			isClass: false,
			name: ""
		};
	}

	static function classShape(cls:ClassType, pos:Position, noConstructorMessage:String, nonFieldMessage:String):RecordShapeData {
		final ctor = cls.constructor;
		if(ctor == null) {
			Context.fatalError(noConstructorMessage, pos);
		}
		final args = switch(ctor.get().type) {
			case TFun(args, _): args;
			default:
				Context.fatalError(noConstructorMessage, pos);
		};
		if(args.length == 0) {
			Context.fatalError(noConstructorMessage, pos);
		}

		final fields = new Map<String, ClassField>();
		for(field in cls.fields.get()) {
			fields.set(field.name, field);
		}

		final names:Array<String> = [];
		final fieldTypes:Array<Type> = [];
		for(arg in args) {
			final field = fields.get(arg.name);
			if(field == null) {
				Context.fatalError(nonFieldMessage, pos);
			}
			names.push(arg.name);
			fieldTypes.push(field.type);
		}
		return {names: names, fieldTypes: fieldTypes, isClass: true, name: cls.name};
	}

	static function isRecordType(type:Type):Bool {
		return switch(Context.follow(type)) {
			case TInst(c, _): c.get().meta.has(":dataClass");
			case _: false;
		};
	}

	public static function fieldNames(receiver:Expr, message:String):Array<String> {
		return of(receiver, message).names;
	}
	#end
}
