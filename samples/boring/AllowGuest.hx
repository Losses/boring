package boring;

class AllowGuest {
    public function new() {}

    public static function useStatic(v:Int):Int {
        return AllowHost.secretStatic(v);
    }

    public static function useCounter():Int {
        // The shared counter takes the compound form: its read and its store
        // happen under one lock. (P-1a compound operation)
        AllowHost.counter += 2;
        return AllowHost.counter;
    }

    public function useMethod():String {
        final h = new AllowHost();
        return h.secretMethod() + h.tag;
    }
}
