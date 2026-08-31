package tests;

import boring.FnValuesOps;
import boring.FnValuesOps.BuiltInNameResolver;
import std.Test;

class FnValuesTests {
	@:test("function-typed fields stored and invoked")
	public static function testFieldInvocation():Void {
		final ops = new FnValuesOps(function(index:Int) return "s" + index, new BuiltInNameResolver());
		Test.equals("s3", ops.styleLabel(3));
		Test.equals("built-in:cjk", ops.resolveLabel("cjk"));
	}

	@:test("function-typed parameter invoked inside the callee")
	public static function testParameterInvocation():Void {
		Test.equals("i1", FnValuesOps.applyPicker(["a", "b"], function(index:Int) return "i" + index));
	}

	@:test("generic function-typed parameter")
	public static function testGenericParameter():Void {
		Test.equals(6, FnValuesOps.mapOne(5, function(item:Int) return item + 1));
		Test.equals("x!", FnValuesOps.mapOne("x", function(item:String) return item + "!"));
	}

	@:test("local function value stored and invoked")
	public static function testStoredLocal():Void {
		Test.equals("u19968", FnValuesOps.storedLocal());
	}

	@:test("function value returned from a function")
	public static function testReturnedFunction():Void {
		final prefixed = FnValuesOps.makePrefixer("pre-");
		Test.equals("pre-suffix", prefixed("suffix"));
	}

	@:test("static function-typed field invoked")
	public static function testStaticField():Void {
		Test.equals("tag7", FnValuesOps.defaultTag(7));
	}
}
