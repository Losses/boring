package std;

/**
 * Standard library extern for grapheme cluster access
 * (docs/specs/stdlib/11-grapheme-clusters.md). A grapheme cluster is a
 * user-perceived character under UAX #29: a base with its combining
 * marks, a Hangul syllable run, an emoji sequence with modifiers or
 * joiners, or a regional-indicator pair. References route through each
 * target's import table to the compiled resident module
 * runtime.Graphemes, the one implementation every target and the
 * stage-one harness execute.
 */
extern class Graphemes {
	public static function count(s:String):Int;
	public static function at(s:String, index:Int):Null<String>;
	public static function slice(s:String, from:Int, to:Int):String;
	public static function parts(s:String):Array<String>;
}
