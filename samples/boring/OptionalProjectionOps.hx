package boring;

#if swift_output
import boring.ValueTypeOps.FontFaceId;
import boring.ValueTypeOps.Ic;

/**
    Optional receivers whose member is a projection or a string
    conversion: a narrowed value-type method call, a `StringTools.trim`
    on a guarded nullable string, and a record whose fields are nullable
    value types printed through the generated `toString`.
*/
class OptionalProjectionOps {
    public static function recordText(font:Null<FontFaceId>, fonts:Array<Null<FontFaceId>>):String {
        return Std.string(new ProjectionRecord(font, fonts));
    }

    public static function toPx(emPx:Float, value:Null<Ic>):Float {
        if (value == null)
            return 0.0;
        return value.toPx(emPx);
    }

    public static function trimDetail(status:Null<String>, detail:Null<String>):String {
        if (status == null)
            return "none";
        if (detail == null)
            return status;
        final trimmed = StringTools.trim(detail);
        if (trimmed == "")
            return status;
        return status + ":" + trimmed;
    }
}

@:dataClass
class ProjectionRecord {
    public final font:Null<FontFaceId>;
    public final fonts:Array<Null<FontFaceId>>;

    public function new(font:Null<FontFaceId>, fonts:Array<Null<FontFaceId>>) {
        this.font = font;
        this.fonts = fonts;
    }
}
#else
class OptionalProjectionOps {}
class ProjectionRecord {}
#end
