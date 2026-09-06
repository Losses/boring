package boring;

class AllowGuest {
    public function new() {}

    public static function useStatic(v:Int):Int {
        return AllowHost.secretStatic(v);
    }

    public static function useCounter():Int {
        AllowHost.counter = AllowHost.counter + 2;
        return AllowHost.counter;
    }

    public function useMethod():String {
        final h = new AllowHost();
        return h.secretMethod() + h.tag;
    }
}
