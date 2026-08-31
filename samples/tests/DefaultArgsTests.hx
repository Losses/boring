package tests;

import boring.DefaultArgsOps;
import std.Test;

class DefaultArgsTests {
	@:test("greet with explicit and default prefix")
	public static function testGreet():Void {
		Test.equals("Greetings Ada", DefaultArgsOps.callGreet0());
		Test.equals("Hello Ada", DefaultArgsOps.callGreet1());
	}

	@:test("configure with zero, one, two, and three omitted arguments")
	public static function testConfigure():Void {
		Test.equals(-180.0, DefaultArgsOps.callConfigure0());
		Test.equals(180.0, DefaultArgsOps.callConfigure1());
		Test.equals(300.0, DefaultArgsOps.callConfigure2());
		Test.equals(275.0, DefaultArgsOps.callConfigure3());
	}

	@:test("formatLabel instance method with nullable and value optional parameters")
	public static function testFormatLabel():Void {
		Test.equals("item:formatted", DefaultArgsOps.callFormatLabel0());
		Test.equals("item-formatted", DefaultArgsOps.callFormatLabel1());
		Test.equals("none-default", DefaultArgsOps.callFormatLabel2());
	}

	@:test("describeTag with explicit null default")
	public static function testDescribeTag():Void {
		Test.equals("alpha:extra", DefaultArgsOps.callDescribeTag0());
		Test.equals("alpha:none", DefaultArgsOps.callDescribeTag1());
	}

	@:test("openMode with zero-argument enum constructor default")
	public static function testOpenMode():Void {
		Test.equals("write:1", DefaultArgsOps.callOpenMode0());
		Test.equals("read:1", DefaultArgsOps.callOpenMode1());
	}

	@:test("adjust with negative literal default")
	public static function testAdjust():Void {
		Test.equals(30.0, DefaultArgsOps.callAdjust0());
		Test.equals(15.0, DefaultArgsOps.callAdjust1());
	}

	@:test("coalescing infinity default preserves explicit values")
	public static function testCoalescingInfinity():Void {
		Test.equals(Math.POSITIVE_INFINITY, DefaultArgsOps.callInfinity0());
		Test.equals(1.25, DefaultArgsOps.callInfinity1());
	}

	@:test("coalescing array defaults are fresh per constructor call")
	public static function testCoalescingArrayFreshness():Void {
		final first = new DefaultArgsOps().familyNames;
		final second = new DefaultArgsOps().familyNames;
		first.push("serif");
		Test.equals(1, first.length);
		Test.equals(0, second.length);
	}

	@:test("coalescing map defaults are fresh per function call")
	public static function testCoalescingMapFreshness():Void {
		final first = DefaultArgsOps.callMapDefault();
		final second = DefaultArgsOps.callMapDefault();
		first.set("serif", 1);
		Test.equals(true, first.exists("serif"));
		Test.equals(false, second.exists("serif"));
	}

	@:test("local function with default argument called with omission")
	public static function testLocalFunction():Void {
		Test.equals(107, DefaultArgsOps.callLocal());
		Test.equals(207, DefaultArgsOps.callLocalB());
	}

	@:test("interface method with default parameter called through interface")
	public static function testInterfaceMethod():Void {
		Test.equals("Admin:Sam", DefaultArgsOps.callInterface0());
		Test.equals("User:Sam", DefaultArgsOps.callInterface1());
	}

	// --- Extension grammar roots: coalescing defaults that read parameters or static fields ---

	@:test("bare earlier-parameter read")
	public static function testParameterRead():Void {
		Test.equals("hello", DefaultArgsOps.greetWithPrefix("hello"));
		Test.equals("hi", DefaultArgsOps.greetWithPrefix("hello", "hi"));
	}

	@:test("field access over a parameter")
	public static function testFieldAccess():Void {
		Test.equals("size:2", DefaultArgsOps.sizeLabel(["a", "b"]));
		Test.equals("size:0", DefaultArgsOps.sizeLabel());
	}

	@:test("conditional over a parameter")
	public static function testConditional():Void {
		Test.equals("English", DefaultArgsOps.localeSample("en"));
		Test.equals("french", DefaultArgsOps.localeSample("fr", "french"));
	}

	@:test("static-field read")
	public static function testStaticFieldRead():Void {
		Test.equals(Math.POSITIVE_INFINITY, DefaultArgsOps.staticFieldSample(1));
		Test.equals(5.0, DefaultArgsOps.staticFieldSample(5, 1.0));
	}

	@:test("dependence assertion: different earlier arguments resolve differently")
	public static function testDependence():Void {
		Test.equals("alpha", DefaultArgsOps.callDependenceA());
		Test.equals("beta", DefaultArgsOps.callDependenceB());
	}
}
