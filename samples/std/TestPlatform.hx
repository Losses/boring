package std;

/**
 * Host edges of the resident runtime.TestCore
 * (docs/specs/features/19-testing.md). The assertion checks and message
 * formatting are pure logic that lives in the Haxe source; these four
 * primitives are the parts each target provides natively: raising the
 * canonical failure message, reading the test id the host runner tracks,
 * and rendering a plain number without the special values. Each target
 * lowers these statics inline; no runtime module implements them, and the
 * stage-one harness binds this extern to tests/haxe/TestPlatform.hx.
 * Business code never calls them; a reference outside the resident module
 * is a compile error.
 */
extern class TestPlatform {
	/** Abort with the canonical failure message; never returns. */
	public static function raise(canonical:String):Void;

	/** The id of the running test, empty when none is running. */
	public static function currentTestId():String;

	/** The decimal rendering of an integer. */
	public static function intToString(v:Int):String;

	/** The decimal rendering of a float without the special values. */
	public static function floatToString(v:Float):String;
}
