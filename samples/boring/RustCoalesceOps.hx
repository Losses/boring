package boring;

class RustCoalesceRecord {
    public final fontFamilies:Array<String>;
    public final fontSize:Float;
    public final locale:String;
    public final fontWeight:Int;
    public final italic:Bool;

    public function new(?fontFamilies:Array<String>, ?fontSize:Null<Float> = 16.0, ?locale:Null<String> = "zh-Hans", ?fontWeight:Null<Int> = 400,
            ?italic:Null<Bool> = false) {
        this.fontFamilies = fontFamilies == null ? [] : fontFamilies;
        this.fontSize = fontSize == null ? 16.0 : fontSize;
        this.locale = locale == null ? "zh-Hans" : locale;
        this.fontWeight = fontWeight == null ? 400 : fontWeight;
        this.italic = italic == null ? false : italic;
    }
    public function describe():String {
        return locale + ":" + Std.string(fontSize) + ":" + Std.string(fontWeight)
            + ":" + Std.string(italic) + ":" + Std.string(fontFamilies.length);
    }
}

class RustCoalesceHolder {
    public final record:RustCoalesceRecord;

    public function new(record:Null<RustCoalesceRecord>) {
        this.record = record == null ? new RustCoalesceRecord() : record;
    }

    public function describe():String {
        return record.describe();
    }
}

class RustCoalesceOps {
    public static function resolve(?value:RustCoalesceRecord):String {
        return new RustCoalesceHolder(value).describe();
    }
}
