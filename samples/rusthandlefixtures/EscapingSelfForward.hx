package rusthandlefixtures;

#if rust_output
/**
    A shared-interface implementor whose method forwards this to a
    handle-taking static callee. The escaping scan registers the class in
    escapingHandleClassKeys, so the receiver lowers to
    this: &Rc<RefCell<Self>> and the forward passes the real handle instead
    of a value copy. (TraitIdentityAdapter)
*/
@:sharedHandle
interface ForwardSink {
    function forwardA():String;
}

class ForwardWorker implements ForwardSink {
    public function new() {}

    public function forwardA():String {
        return ForwardWorker.takeHandle(this);
    }

    public static function takeHandle(host:ForwardWorker):String {
        return "fwd";
    }
}

class EscapingSelfForwardOps {
    public static function run():String {
        // Bound to a local first: this fixture pins the escaping-self
        // forward (the scan + handle receiver); the chained-new
        // receiver shape belongs to ChainedNewForward.
        // (TraitIdentityAdapter)
        final worker = new ForwardWorker();
        return worker.forwardA();
    }
}
#end
