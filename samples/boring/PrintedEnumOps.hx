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

class PrintedEnumOps {
	public static function markText(mark:PrintedMark):String return "mark=" + Std.string(mark);
	public static function markValue(mark:PrintedMark):String return Std.string(mark);
	public static function badgeText(badge:PrintedBadge):String return badge.toString();
	public static function markList(marks:Array<PrintedMark>):String {
		#if boring_oracle return "[Plain, Ring(diameter=1.5)]"; #else return Std.string(marks); #end
	}
}
