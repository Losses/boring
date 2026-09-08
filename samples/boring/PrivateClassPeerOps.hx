package boring;

class PrivateClassPeerOps {
    public static function resolve():String {
        return new Resolution("second").value;
    }
}

private class Resolution {
    public final value:String;

    public function new(value:String) {
        this.value = value;
    }
}
