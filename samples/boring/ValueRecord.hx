/**
 * A class record (feature spec 27): public constructor-parameter fields,
 * a validating constructor body, and a getter-only property. The
 * `@:dataClass` marker renders the Kotlin tree as a data class; record
 * behavior on stage 1 and the other trees comes from the std record
 * macros (std.RecordCopy, std.RecordEq, std.RecordStr).
 */
package boring;

@:dataClass
class ValueRecord {
	public final start:Int;
	public final end:Int;
	public final label:String;

	public var length(get, never):Int;

	public function new(start:Int, end:Int, label:String) {
		if (start > end) {
			throw new ValueException(StartAfterEnd);
		}
		if (start < 0) {
			throw new ValueException(NegativeStart);
		}
		this.start = start;
		this.end = end;
		this.label = label;
	}

	public function get_length():Int {
		return end - start;
	}
}
