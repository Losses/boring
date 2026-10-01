package boring;

/**
 * R1 regression sample (CharCodeNoToString): the String.fromCharCode
 * template already produces a String, so its result must not carry a
 * redundant toString call.
 **/
class FromCharCodeToString {
	public static function render(code:Int):String {
		return String.fromCharCode(code);
	}
}
