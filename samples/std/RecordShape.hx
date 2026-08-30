package std;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
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
	public static function of(receiver:Expr, message:String):{names:Array<String>, isClass:Bool, name:String} {
		final type = try {
			Context.typeof(receiver);
		} catch (e:Dynamic) {
			Context.fatalError(message, receiver.pos);
		}
		switch(Context.follow(type)) {
			case TAnonymous(a):
				final anon = a.get();
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
				final names:Array<String> = [];
				for(i in 0...fields.length) {
					names.push(fields[i].name);
				}
				return { names: names, isClass: false, name: "" };
			case TInst(c, _):
				final cls = c.get();
				if(!cls.meta.has(":dataClass")) {
					Context.fatalError(message, receiver.pos);
				}
				final ctor = cls.constructor;
				if(ctor == null) {
					Context.fatalError("record operations require at least one constructor parameter", receiver.pos);
				}
				final args = switch(ctor.get().type) {
					case TFun(args, _): args;
					default:
						Context.fatalError("record operations require at least one constructor parameter", receiver.pos);
				};
				final fieldNames:Array<String> = [];
				final fields = cls.fields.get();
				for(i in 0...fields.length) {
					fieldNames.push(fields[i].name);
				}
				final names:Array<String> = [];
				for(i in 0...args.length) {
					final argName = args[i].name;
					if(fieldNames.indexOf(argName) < 0) {
						Context.fatalError("record copy requires every constructor parameter to be a class field", receiver.pos);
					}
					names.push(argName);
				}
				return { names: names, isClass: true, name: cls.name };
			default:
				return Context.fatalError(message, receiver.pos);
		}
	}

	public static function fieldNames(receiver:Expr, message:String):Array<String> {
		return of(receiver, message).names;
	}
	#end
}
