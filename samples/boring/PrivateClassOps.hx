package boring;

class PrivateClassOps {
    public static function resolve():String {
        return new Resolution("first").value;
    }
}

private class Resolution {
    public final value:String;

    public function new(value:String) {
        this.value = value;
    }
}
