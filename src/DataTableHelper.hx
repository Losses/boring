#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import haxe.macro.Type.ClassField;
import haxe.macro.Type.TypedExprDef;

/**
 * Shared compiler-level detection for compile-time data tables
 * per docs/specs/features/20-compile-time-data-tables.md.
 *
 * A constant Array<Int> with > 64 elements follows the table emission form;
 * arrays with <= 64 elements follow existing unrolling rules.
 */
class DataTableHelper {
	public static final THRESHOLD:Int = 64;

	public static function isDataTableField(field:ClassField):Bool {
		if (field == null || !field.isFinal || field.expr == null) {
			return false;
		}
		final e = field.expr();
		if (e == null) {
			return false;
		}
		return getDataTableElements(e) != null;
	}

	public static function getDataTableElements(e:TypedExpr):Null<Array<Int>> {
		if (e == null) {
			return null;
		}
		return switch (e.expr) {
			case TypedExprDef.TArrayDecl(elements):
				if (elements.length <= THRESHOLD) {
					return null;
				}
				final ints:Array<Int> = [];
				for (elem in elements) {
					switch (elem.expr) {
						case TypedExprDef.TConst(TInt(val)):
							ints.push(val);
						case _:
							return null;
					}
				}
				ints;
			case _: null;
		};
	}
}
#end
