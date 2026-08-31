package tests;
import boring.PrintedEnumOps;
import boring.PrintedEnumOps.PrintedMark;
import boring.FloatWidth;
import boring.PrintedEnumOps.PrintedBadge;
import std.Test;

// Stage 1 prints payload enum values natively without labels (Ring(1.5),
// Tag(x,2)); the generated targets print the ruled labeled forms. Every row
// that carries a payload enum value asserts through the boring_oracle
// conditional, the array-row pattern of stdlib spec 12.
class PrintedEnumTests {
	@:test("enum constructor printed forms")
	public static function forms():Void {
		Test.equals("Plain", PrintedEnumOps.markValue(Plain));
		#if boring_oracle
		Test.equals("mark=Ring(1.5)", PrintedEnumOps.markText(Ring(1.5)));
		#else
		Test.equals("mark=Ring(diameter=1.5)", PrintedEnumOps.markText(Ring(1.5)));
		#end
		final label = "x";
		#if boring_oracle
		Test.equals("Tag(x,2)", PrintedEnumOps.markValue(Tag(label, 2)));
		#else
		Test.equals("Tag(text=x, weight=2)", PrintedEnumOps.markValue(Tag(label, 2)));
		#end
		#if boring_oracle
		Test.equals("PrintedBadge(mark=Ring(1.5), width=F64)", PrintedEnumOps.badgeText(new PrintedBadge(Ring(1.5), F64)));
		#else
		Test.equals("PrintedBadge(mark=Ring(diameter=1.5), width=F64)", PrintedEnumOps.badgeText(new PrintedBadge(Ring(1.5), F64)));
		#end
		#if boring_oracle
		Test.equals("[Plain,Ring(1.5)]", PrintedEnumOps.markList([Plain, Ring(1.5)]));
		#else
		Test.equals("[Plain, Ring(diameter=1.5)]", PrintedEnumOps.markList([Plain, Ring(1.5)]));
		#end
	}
}
