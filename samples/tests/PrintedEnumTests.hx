package tests;
import boring.PrintedEnumOps;
import boring.PrintedEnumOps.PrintedMark;
import boring.FloatWidth;
import boring.PrintedEnumOps.PrintedBadge;
import std.Test;
class PrintedEnumTests {
	@:test("enum constructor printed forms")
	public static function forms():Void {
		Test.equals("Plain", PrintedEnumOps.markValue(Plain));
		Test.equals("Ring(diameter=1.5)", PrintedEnumOps.markText(Ring(1.5)));
		Test.equals("Tag(text=x, weight=2)", PrintedEnumOps.markValue(Tag("x", 2)));
		Test.equals("PrintedBadge(mark=Ring(diameter=1.5), width=F64)", PrintedEnumOps.badgeText(new PrintedBadge(Ring(1.5), F64)));
		#if boring_oracle
		Test.equals("[Plain, Ring(diameter=1.5)]", PrintedEnumOps.markList([Plain, Ring(1.5)]));
		#else
		Test.equals("[Plain, Ring(diameter=1.5)]", PrintedEnumOps.markList([Plain, Ring(1.5)]));
		#end
	}
}
