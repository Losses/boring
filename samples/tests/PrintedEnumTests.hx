package tests;
import boring.PrintedEnumOps;
import boring.PrintedEnumOps.PrintedMark;
import boring.FloatWidth;
import boring.PrintedEnumOps.PrintedBadge;
import std.Test;

// Stage 1 prints payload enum values with declaration-side labels in every
// generated target.
class PrintedEnumTests {
	@:test("enum constructor printed forms")
	public static function forms():Void {
		Test.equals("Plain", PrintedEnumOps.markValue(Plain));
		Test.equals("mark=Ring(diameter=1.5)", PrintedEnumOps.markText(Ring(1.5)));
		final label = "x";
		Test.equals("Tag(text=x, weight=2)", PrintedEnumOps.markValue(Tag(label, 2)));
		Test.equals("PrintedBadge(mark=Ring(diameter=1.5), width=F64)", PrintedEnumOps.badgeText(new PrintedBadge(Ring(1.5), F64)));
		Test.equals("[Plain, Ring(diameter=1.5)]", PrintedEnumOps.markList([Plain, Ring(1.5)]));
	}
}
