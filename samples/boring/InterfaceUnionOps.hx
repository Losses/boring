package boring;

#if rust_output
import boring.HaxeExceptionOps.HaxeExceptionFault;

interface InterfaceUnionSlot {
    public function run(value:Int):Int;
}

class InterfaceUnionAlpha implements InterfaceUnionSlot {
    public function new() {}

    public function run(value:Int):Int {
        if (value < 0)
            throw new HaxeExceptionFault("alpha");
        return value;
    }
}

/**
    Two implementations in separate modules throw different failure
    identities. The interface method has no body, so its trait signature
    takes the union of the implementing bodies; the call through the
    interface receiver propagates that union.
**/
class InterfaceUnionOps {
    public static function call(slot:InterfaceUnionSlot, value:Int):Int {
        return slot.run(value);
    }
}
#else
class InterfaceUnionOps {}
#end
