package boring;

#if rust_output
/**
    A nullable value narrowed by a null guard and returned through a fallible
    function. The match binding names a reference to the inner text, so the
    owned String return slot clones the referent at the boundary. The named
    narrowedOptionReturn rule covers the fallible return position.
*/
class NarrowedOptionReturnOps {
    public static function pick(value:Null<String>):String {
        if (value != null)
            return value;
        throw new NarrowedOptionReturnFault("missing");
    }
}

class NarrowedOptionReturnFault extends haxe.Exception {
    public function new(message:String) {
        super(message);
    }
}
#else
class NarrowedOptionReturnOps {}
#end
