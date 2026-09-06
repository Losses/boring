package boring;

class NullArgsSpan {
    public final label:String;
    public final extra:Null<String>;

    public function new(label:String, ?extra:Null<String>) {
        this.label = label;
        this.extra = extra == null ? "none" : extra;
    }
}

class NullArgsOps {
    public static function explicitNull():String {
        return new NullArgsSpan("a", null).extra;
    }

    public static function nullableVariable(v:Null<String>):String {
        return new NullArgsSpan("a", v).extra;
    }
}
