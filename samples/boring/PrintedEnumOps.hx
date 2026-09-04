package boring;

enum PrintedMark {
    Plain;
    Ring(diameter:Float);
    Tag(text:String, weight:Int);
    Trail(steps:Array<Int>);
    Aliases(names:Array<String>);
}

@:dataClass
class PrintedBadge {
    public final mark:PrintedMark;
    public final width:FloatWidth;

    public function new(mark:PrintedMark, width:FloatWidth) {
        this.mark = mark;
        this.width = width;
    }
}

// Both the stage 1 reference build and the generated targets print payload
// enum values in labeled constructor forms: stage 1 through the
// boring_oracle-only rewrite of samples/std/EnumText.hx, the generated
// targets through the Std.string interception of features/34. The array
// separator row of PrintedEnumTests records the remaining native
// difference. The array argument constructors exercise the ruled array form
// of feature spec 40 ruling 4 on every target including stage 1.
class PrintedEnumOps {
    public static function markText(mark:PrintedMark):String
        return "mark=" + Std.string(mark);

    public static function markValue(mark:PrintedMark):String
        return Std.string(mark);

    public static function badgeText(badge:PrintedBadge):String
        return badge.toString();

    public static function markList(marks:Array<PrintedMark>):String
        return Std.string(marks);
}
