package boring;

#if swift_output
class CtorOptArgHolder {
    public final value:Int;

    public function new(value:Int) {
        this.value = value;
    }
}

/**
    A nullable value that reaches a value-typed constructor parameter needs
    the Swift `!`: a `raw == null ? 0 : raw` ternary coalesces to `raw ?? 0`
    yet Haxe still types the binding nullable, and a guarded nullable
    parameter stays `Int32?` at the call.
*/
class CtorOptArgOps {
    public static function coalesced(raw:Null<Int>):Int {
        final narrowed = raw == null ? 0 : raw;
        return new CtorOptArgHolder(narrowed).value;
    }

    public static function guarded(raw:Null<Int>):Int {
        if (raw == null)
            return -1;
        return new CtorOptArgHolder(raw).value;
    }
}
#else
class CtorOptArgOps {}
#end
