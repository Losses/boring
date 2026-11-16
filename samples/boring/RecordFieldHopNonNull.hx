package boring;

/**
 * R1 regression sample (DeclaredFieldNonNull, record fields): a typedef
 * record field read off a nullable receiver renders through the receiver's
 * double-bang extraction, so a later length read keeps a plain dot. The
 * record field access arrives as FAnon; treating that hop as a propagating
 * nullable chain hop emits a safe call and turns the Int length into Int?,
 * which the Kotlin function return and a non-null Int parameter both reject.
 *
 * Pinned to the main (shipping) unit with @:mainOnly: the test-support
 * closure would otherwise reclassify this module to tests, because its only
 * Haxe referencer is tests.ConsumerShapeCorpusTests (which runs the same hop
 * at runtime). The regression pin reads the generated .kt from the main tree
 * (reference/kotlin/gen/boring/RecordFieldHopNonNull.kt), so the sample must
 * stay in gen. Pinning the unit decides which tree receives the file; the
 * emitted class keeps its shape.
 **/
typedef RecordFieldHopRow = {
	var items:Array<String>;
}

@:mainOnly
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
