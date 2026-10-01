package boring;

/**
 * R1 regression sample (UnusedLocalNaming): a local this pass proves
 * unmentioned renders nothing, never a bare name-and-type declaration
 * swiftc flags as never used.
 **/
class UnusedSwiftBinding {
	public static function compute():Int {
		var unused:Int;
		return 1;
	}
}
