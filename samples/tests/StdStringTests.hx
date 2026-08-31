package tests;

import boring.StdStringOps;
import std.Test;

class StdStringTests {
	@:test("Std.string converts scalar operands inside concatenation")
	public static function concatenatedScalars():Void {
		Test.equals("string=text", StdStringOps.concatString("text"));
		Test.equals("int=42", StdStringOps.concatInt(42));
		Test.equals("float=2.5", StdStringOps.concatFloat(2.5));
		Test.equals("bool=true", StdStringOps.concatBool(true));
	}

	@:test("Std.string converts standalone scalar operands")
	public static function standaloneScalars():Void {
		Test.equals("text", StdStringOps.stringValue("text"));
		Test.equals("42", StdStringOps.intValue(42));
		Test.equals("2.5", StdStringOps.floatValue(2.5));
		Test.equals("false", StdStringOps.boolValue(false));
	}
}
