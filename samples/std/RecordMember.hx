package std;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

/**
 * Stage 1 build macro for the printed member of class records
 * (docs/specs/features/31-record-tostring-member.md). The generated field
 * carries a marker so Kotlin can keep its native data-class synthesis.
 */
class RecordMember {
	macro public static function build():Array<Field> {
		final fields = Context.getBuildFields();
		final localClass = Context.getLocalClass();
		if(localClass == null || !localClass.get().meta.has(":dataClass")) {
			return fields;
		}

		for(field in fields) {
			if(field.name != "toString") {
				continue;
			}
			switch(field.kind) {
				case FFun(fun) if(fun.args.length == 0):
					return fields;
				case _:
			}
		}

		final shape = RecordShape.local(fields);
		final pos = Context.currentPos();
		final receiver:Expr = {expr: EConst(CIdent("this")), pos: pos};
		final printed = RecordShape.assemble(receiver, shape);
		final body:Expr = {
			expr: EBlock([{expr: EReturn(printed), pos: pos}]),
			pos: pos
		};
		fields.push({
			name: "toString",
			doc: "Synthesized record printed form.",
			meta: [{name: ":recordMember", params: [], pos: pos}],
			access: [APublic],
			kind: FFun({args: [], ret: macro :String, expr: body}),
			pos: pos
		});
		return fields;
	}
}
#end
