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
}
