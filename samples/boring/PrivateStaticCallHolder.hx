package boring;

// A private static method referenced by class name from a public static
// (mirrors LineCandidate.emptyHanging). The Dart declaration lowers the
// private static under its `_`-prefixed name; the reference must match.

class PrivateStaticCallHolder {
    public final value:String;

    public function new(value:String) {
        this.value = value;
    }

    static function empty():PrivateStaticCallHolder {
        return new PrivateStaticCallHolder("empty");
    }

    public static function make(?v:Null<String>):PrivateStaticCallHolder {
        return v == null ? PrivateStaticCallHolder.empty() : new PrivateStaticCallHolder(v);
    }
}