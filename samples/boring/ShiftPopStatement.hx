package boring;

/**
 * R1 regression sample (NullArmStatementFold): statement-position
 * shift/pop discards the removed element, so the guarded removal must
 * render as a statement, not as an if-else expression whose unused
 * value warns.
 **/
class ShiftPopStatement {
	public static function drain(items:Array<Int>):Void {
		items.pop();
		items.shift();
	}
}
