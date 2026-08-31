package tests;

import boring.StdStringOps;
import boring.FloatWidth;
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

	@:test("Std.string converts value enumeration operands to constructor names")
	public static function valueEnumerations():Void {
		Test.equals("enum=F64", StdStringOps.concatEnum(FloatWidth.F64));
		Test.equals("F16", StdStringOps.enumValue(FloatWidth.F16));
		Test.equals(true, StdStringOps.enumMatchesConstructor());
	}

	@:test("Std.string renders arrays with ruled separators and element forms")
	public static function arrays():Void {
		Test.equals("[1, 2, 3]", StdStringOps.intArray());
		Test.equals("[alpha, beta]", StdStringOps.stringArray());
		Test.equals("[1.5, 2.25]", StdStringOps.floatArray());
		Test.equals("[true, false]", StdStringOps.boolArray());
		Test.equals("[F64, F16]", StdStringOps.enumArray());
		Test.equals("[]", StdStringOps.emptyArray());
		Test.equals("[[1, 2], [3]]", StdStringOps.nestedArray());
		Test.equals("[alpha, beta]", StdStringOps.readOnlyArray());
	}
}
