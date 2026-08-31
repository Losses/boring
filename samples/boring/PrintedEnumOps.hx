package boring;

enum PrintedMark {
	Plain;
	Ring(diameter:Float);
	Tag(text:String, weight:Int);
}

@:dataClass
class PrintedBadge {
	public final mark:PrintedMark;
	public final width:FloatWidth;
	public function new(mark:PrintedMark, width:FloatWidth) { this.mark = mark; this.width = width; }
}

// Stage 1 prints payload enum values natively without labels; the generated
// targets print the ruled labeled forms through the Std.string interception
// of features/34. The divergence is recorded in PrintedEnumTests.
class PrintedEnumOps {
	public static function markText(mark:PrintedMark):String return "mark=" + Std.string(mark);
	public static function markValue(mark:PrintedMark):String return Std.string(mark);
	public static function badgeText(badge:PrintedBadge):String return badge.toString();
	public static function markList(marks:Array<PrintedMark>):String return Std.string(marks);
}
