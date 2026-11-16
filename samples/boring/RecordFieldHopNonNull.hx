package boring;

/**
 * R1 regression sample (DeclaredFieldNonNull, record fields): a typedef
 * record field read off a nullable receiver renders through the receiver's
 * double-bang extraction, so a later length read keeps a plain dot. A record
 * field is an FAnon access rather than an FInstance one; treating it as a
 * propagating nullable chain hop emits a safe call and turns the Int length
 * into Int?, which the Kotlin function return and a non-null Int parameter
 * both reject.
 **/
typedef RecordFieldHopRow = {
	var items:Array<String>;
}

class RecordFieldHopNonNull {
	static function take(value:Int):Int {
		return value;
	}

	/** Return position typed Int: the hop must not widen the length to Int?. */
	public static function readLength(r:Null<RecordFieldHopRow>):Int {
		return r.items.length;
	}

	/** Non-null Int parameter: the hop must not render a nullable argument. */
	public static function readLengthArgument(r:Null<RecordFieldHopRow>):Int {
		return take(r.items.length);
	}
}
