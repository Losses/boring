package boring;

class NullArgsSpan {
    public final label:String;
    public final extra:Null<String>;

    public function new(label:String, ?extra:Null<String>) {
        this.label = label;
        this.extra = extra == null ? "none" : extra;
    }
}

class NullDefaultSpan {
    public final tier:Null<String>;

    public function new(?tier:Null<String>) {
        this.tier = tier == null ? null : tier;
    }
}

class NullArgsOps {
    public static function explicitNull():String {
        return new NullArgsSpan("a", null).extra;
    }

    public static function nullableVariable(v:Null<String>):String {
        return new NullArgsSpan("a", v).extra;
    }

    public static function conditionalArg(v:Null<String>):String {
        return new NullArgsSpan("a", v == null ? "none" : v).extra;
    }

    public static function nullDefaultAbsent():String {
        return new NullDefaultSpan(null).tier == null ? "null" : "set";
    }

    public static function nullDefaultPresent():String {
        return new NullDefaultSpan("x").tier == null ? "null" : "set";
    }
}
