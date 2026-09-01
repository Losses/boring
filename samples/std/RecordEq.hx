package std;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
#end

/**
 * Structural equality for records, as ruled in
 * docs/specs/features/27-class-members-and-records.md. The macro expands
 * at the call site into a field-wise `==` comparison joined with `&&`,
 * so stage 1 and every language tree run the same lowered code. Class
 * records (a class carrying `@:dataClass`) compare the fields held by
 * constructor parameters, in the declaration order of those fields
 * (docs/specs/features/37-record-print-field-order.md); anonymous
 * records compare all fields in declaration order.
 */
class RecordEq {
	public static macro function eq(a:Expr, b:Expr):Expr {
		final names = RecordShape.fieldNames(a, "record eq accepts record receivers only");
		if(names.length == 0) {
			return macro true;
		}
		var out: Expr = null;
		for(i in 0...names.length) {
			final name = names[i];
			final readA = { expr: EField(a, name), pos: a.pos };
			final readB = { expr: EField(b, name), pos: b.pos };
			final piece = { expr: EBinop(OpEq, readA, readB), pos: a.pos };
			out = out == null ? piece : { expr: EBinop(OpBoolAnd, out, piece), pos: a.pos };
		}
		return out;
	}
}
