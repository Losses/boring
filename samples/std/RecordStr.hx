package std;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
#end

/**
 * Printed form of a record, as ruled in
 * docs/specs/features/27-class-members-and-records.md. The macro expands
 * at the call site into a string concatenation producing
 * `Name(field=value, ...)` for class records and `{ field=value, ... }`
 * for anonymous records, with `, ` between fields. The text matches what
 * the Kotlin `data class` synthesis prints, so stage 1, every language
 * tree, and hand-written Kotlin consumers read the same string.
 */
class RecordStr {
	public static macro function str(r:Expr):Expr {
		final shape = RecordShape.of(r, "record str accepts record receivers only");
		return RecordShape.assemble(r, shape);
	}
}
