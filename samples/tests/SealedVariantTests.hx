package tests;

import boring.SealedVariantOps;
import boring.SealedVariantOps.DotDrawKind;
import boring.SealedVariantOps.DrawKind;
import boring.SealedVariantOps.NoneDrawKind;
import boring.SealedVariantOps.StripeDrawKind;
import std.Test;

class SealedVariantTests {
	@:test("singleton variant prints its bare name")
	public static function testSingletonToString():Void {
		Test.equals("NoneDrawKind", NoneDrawKind.instance.toString());
		Test.equals("NoneDrawKind", Std.string(NoneDrawKind.instance));
		Test.equals("NoneDrawKind", SealedVariantOps.noneLabel());
	}

	@:test("record variants print fields in parameter order")
	public static function testRecordToString():Void {
		final stripe = new StripeDrawKind(1.5, 0.5);
		final dot = new DotDrawKind(2.25, 0.75);
		Test.equals("StripeDrawKind(strokeWidth=1.5, gapLength=0.5)", stripe.toString());
		Test.equals("DotDrawKind(dotDiameter=2.25, gapLength=0.75)", dot.toString());
	}

	@:test("variant labels distinguish all three classes")
	public static function testLabels():Void {
		Test.equals("none", SealedVariantOps.labelOf(NoneDrawKind.instance));
		Test.equals("stripe", SealedVariantOps.labelOf(new StripeDrawKind(1.5, 0.5)));
		Test.equals("dot", SealedVariantOps.labelOf(new DotDrawKind(2.25, 0.75)));
	}

	@:test("variant type checks include the interface and reject siblings")
	public static function testTypeChecks():Void {
		final _none = NoneDrawKind.instance;
		final _stripe = new StripeDrawKind(1.5, 0.5);
		final _dot = new DotDrawKind(2.25, 0.75);
		Test.equals(true, Std.isOfType(_none, DrawKind));
		Test.equals(true, Std.isOfType(_stripe, DrawKind));
		Test.equals(true, Std.isOfType(_dot, DrawKind));
		Test.equals(false, Std.isOfType(_none, StripeDrawKind));
		Test.equals(false, Std.isOfType(_stripe, DotDrawKind));
		Test.equals(false, Std.isOfType(_dot, NoneDrawKind));
	}
}
