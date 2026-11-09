package rusthandlefixtures;

#if rust_output
/**
    Pins the chained-new receiver shape on its own: `new C().method()`
    constructs the gated implementor directly in the call-receiver
    position. The constructor of a handle-ABI class already returns the
    Rc<RefCell<Self>> handle, so the receiver must bind it as-is -- a
    second Rc::new(RefCell::new(...)) wrap here would double the
    Rc<RefCell> and fail the call with E0308. (TraitIdentityAdapter)
*/
@:sharedHandle
interface ChainedSink {
    function run():String;
}

class ChainedWorker implements ChainedSink {
    public function new() {}

    public function run():String {
        return ChainedWorker.takeHandle(this);
    }

    public static function takeHandle(host:ChainedWorker):String {
        return "chained";
    }
}

class ChainedNewForwardOps {
    public static function run():String {
        return new ChainedWorker().run();
    }
}
#end
