package std;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
#end

class RecordCopy {
	public static macro function copy(receiver:Expr, overrides:Array<Expr>):Expr {
		final receiverType = try {
			Context.typeof(receiver);
		} catch (e:Dynamic) {
			Context.fatalError("record copy overrides fields of the receiver record only", receiver.pos);
		};
		// A class record (feature spec 27) reconstructs through the
		// constructor: the arguments follow constructor parameter order,
		// each the override or the receiver's field of that parameter.
		// A receiver that is a class without `@:dataClass` stops here;
		// every other shape falls through to the anonymous path.
		switch(Context.follow(receiverType)) {
			case TInst(c, _):
				final cls = c.get();
				if(cls.meta.has(":dataClass")) {
					return classRecordCopy(cls, receiver, overrides);
				}
				Context.fatalError("record copy overrides fields of the receiver record only", receiver.pos);
			case _:
		}
		final anon = switch (Context.follow(receiverType)) {
			case TAnonymous(a): a.get();
			default:
				Context.fatalError("record copy overrides fields of the receiver record only", receiver.pos);
		};

		final overrideMap = new Map<String, Expr>();
		final overridePosMap = new Map<String, Position>();
		final overrideNames:Array<String> = [];
		for (i in 0...overrides.length) {
			final arg = overrides[i];
			switch (arg.expr) {
				case EBinop(OpAssign, left, right):
					switch (left.expr) {
						case EConst(CIdent(name)):
							if (overrideMap.exists(name)) {
								Context.fatalError("duplicate field in record copy override: " + name, arg.pos);
							}
							overrideMap.set(name, right);
							overridePosMap.set(name, arg.pos);
							overrideNames.push(name);
						default:
							Context.fatalError("record copy overrides assign fields by name only", arg.pos);
					}
				default:
					Context.fatalError("record copy overrides assign fields by name only", arg.pos);
			}
		}

		final fieldMap = new Map<String, ClassField>();
		for (i in 0...anon.fields.length) {
			final f = anon.fields[i];
			fieldMap.set(f.name, f);
		}

		for (i in 0...overrideNames.length) {
			final name = overrideNames[i];
			if (!fieldMap.exists(name)) {
				Context.fatalError("record copy overrides fields of the receiver record only", overridePosMap.get(name));
			}
		}

		final sortedFields = anon.fields.copy();
		for (i in 0...sortedFields.length) {
			for (j in (i + 1)...sortedFields.length) {
				if (Context.getPosInfos(sortedFields[i].pos).min > Context.getPosInfos(sortedFields[j].pos).min) {
					final tmp = sortedFields[i];
					sortedFields[i] = sortedFields[j];
					sortedFields[j] = tmp;
				}
			}
		}

		final objFields:Array<ObjectField> = [];
		for (i in 0...sortedFields.length) {
			final field = sortedFields[i];
			final fieldName = field.name;
			final valExpr = if (overrideMap.exists(fieldName)) {
				overrideMap.get(fieldName);
			} else {
				{ expr: EField(receiver, fieldName), pos: receiver.pos };
			};
			objFields.push({ field: fieldName, expr: valExpr });
		}

		return { expr: EObjectDecl(objFields), pos: Context.currentPos() };
	}

	/**
		The class-record expansion (feature spec 27): `new C(...)` with one
		argument per constructor parameter, the override where given and
		the receiver's field otherwise. Overrides name constructor
		parameters only. The helper lives in macro mode; the class stays
		visible in normal mode so `using std.RecordCopy` resolves.
	**/
	#if macro
	static function classRecordCopy(cls:ClassType, receiver:Expr, overrides:Array<Expr>):Expr {
		final ctor = cls.constructor;
		if (ctor == null) {
			Context.fatalError("record copy requires at least one constructor parameter", receiver.pos);
		}
		final args = switch (ctor.get().type) {
			case TFun(args, _): args;
			default:
				Context.fatalError("record copy requires at least one constructor parameter", receiver.pos);
		};
		final fieldNames:Array<String> = [];
		final fields = cls.fields.get();
		for (i in 0...fields.length) {
			fieldNames.push(fields[i].name);
		}
		for (i in 0...args.length) {
			if (fieldNames.indexOf(args[i].name) < 0) {
				Context.fatalError("record copy requires every constructor parameter to be a class field", receiver.pos);
			}
		}

		final overrideMap = new Map<String, Expr>();
		final overridePosMap = new Map<String, Position>();
		final overrideNames:Array<String> = [];
		for (i in 0...overrides.length) {
			final arg = overrides[i];
			switch (arg.expr) {
				case EBinop(OpAssign, left, right):
					switch (left.expr) {
						case EConst(CIdent(name)):
							if (overrideMap.exists(name)) {
								Context.fatalError("duplicate field in record copy override: " + name, arg.pos);
							}
							overrideMap.set(name, right);
							overridePosMap.set(name, arg.pos);
							overrideNames.push(name);
						default:
							Context.fatalError("record copy overrides assign fields by name only", arg.pos);
					}
				default:
					Context.fatalError("record copy overrides assign fields by name only", arg.pos);
			}
		}

		final argNames:Array<String> = [];
		for (i in 0...args.length) {
			argNames.push(args[i].name);
		}
		for (i in 0...overrideNames.length) {
			final name = overrideNames[i];
			if (argNames.indexOf(name) < 0) {
				Context.fatalError("record copy overrides fields of the receiver record only", overridePosMap.get(name));
			}
		}

		final newArgs:Array<Expr> = [];
		for (i in 0...argNames.length) {
			final name = argNames[i];
			newArgs.push(if (overrideMap.exists(name)) {
				overrideMap.get(name);
			} else {
				{ expr: EField(receiver, name), pos: receiver.pos };
			});
		}
		final typePath:TypePath = { pack: cls.pack, name: cls.name };
		return { expr: ENew(typePath, newArgs), pos: Context.currentPos() };
	}
	#end
}
