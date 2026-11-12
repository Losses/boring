package boring;

/**
 * R1 regression sample (NullArmStatementFold): statement-position
 * shift/pop discards the removed element, so the guarded removal must
 * render as a statement, since an if-else expression here leaves an
 * unused value that warns.
 **/
class ShiftPopStatement {
	public static function drain(items:Array<Int>):Void {
		items.pop();
		items.shift();
	}
}
