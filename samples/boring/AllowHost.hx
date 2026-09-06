package boring;

class AllowHost {
    @:allow(boring.AllowGuest)
    private static function secretStatic(v:Int):Int {
        return v + 1;
    }

    @:allow(boring.AllowGuest)
    private function secretMethod():String {
        return "m";
    }

    @:allow(boring.AllowGuest)
    private static var counter:Int = 40;

    @:allow(boring.AllowGuest)
    private var tag:String = "host";

    public function new() {}
}
