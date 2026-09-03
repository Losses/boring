package tests;
import boring.PrintedEnumOps;
import boring.PrintedEnumOps.PrintedMark;
import boring.FloatWidth;
import boring.PrintedEnumOps.PrintedBadge;
import std.Test;

// The stage 1 reference build and every generated target print payload
// enum values in labeled constructor forms. The array separator row keeps
// the one remaining native difference.
class PrintedEnumTests {
	@:test("enum constructor printed forms")
	public static function forms():Void {
		Test.equals("Plain", PrintedEnumOps.markValue(Plain));
		Test.equals("mark=Ring(diameter=1.5)", PrintedEnumOps.markText(Ring(1.5)));
		final label = "x";
		Test.equals("Tag(text=x, weight=2)", PrintedEnumOps.markValue(Tag(label, 2)));
		Test.equals("PrintedBadge(mark=Ring(diameter=1.5), width=F64)", PrintedEnumOps.badgeText(new PrintedBadge(Ring(1.5), F64)));
		#if boring_oracle
		Test.equals("[Plain,Ring(1.5)]", PrintedEnumOps.markList([Plain, Ring(1.5)]));
		#else
		Test.equals("[Plain, Ring(diameter=1.5)]", PrintedEnumOps.markList([Plain, Ring(1.5)]));
		#end
	}
}
