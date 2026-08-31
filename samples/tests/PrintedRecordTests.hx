package tests;

import boring.PrintedCustom;
import boring.PrintedRecord;
import boring.PrintedRecord.PrintedInner;
import std.RecordStr;
import std.Test;

class PrintedRecordTests {
	@:test("synthesized member matches RecordStr")
	public static function memberMatchesMacro():Void {
		final value = new PrintedRecord(7, 1.5, new PrintedInner("Name"));
		Test.equals("PrintedRecord(count=7, ratio=1.5, inner=PrintedInner(name=Name))", value.toString());
		Test.equals(RecordStr.str(value), value.toString());
	}

	@:test("Std.string and concatenation use the member")
	public static function standardStringUsesMember():Void {
		final value = new PrintedRecord(7, 1.5, new PrintedInner("Name"));
		Test.equals(value.toString(), Std.string(value));
		Test.equals(value.toString(), "" + value);
	}

	@:test("nested records use their printed form")
	public static function nestedRecordUsesMember():Void {
		final value = new PrintedRecord(7, 1.5, new PrintedInner("Name"));
		Test.equals("PrintedInner(name=Name)", value.inner.toString());
		Test.equals("PrintedRecord(count=7, ratio=1.5, inner=PrintedInner(name=Name))", value.toString());
	}

	@:test("explicit printed member wins")
	public static function explicitMemberWins():Void {
		Test.equals("custom=9", new PrintedCustom(9).toString());
	}
}
