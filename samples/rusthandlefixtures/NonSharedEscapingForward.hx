package rusthandlefixtures;

#if rust_output
/**
    A non-@:sharedHandle interface implementor whose method forwards this
    to a callee that takes the interface slot. The interface slot lowers to
    Rc<RefCell<dyn PlainSink>> regardless of @:sharedHandle (RustType), so
    the forward needs handle identity even though P-16 does not apply.
    The ops entry also dispatches through a slot, which forces the adapter
    to satisfy the trait. (P-4a / TraitIdentityAdapter)
*/
interface PlainSink {
    function run():String;
}

class PlainWorker implements PlainSink {
    public function new() {}

    public function run():String {
        return PlainWorker.take(this);
    }

    public static function take(sink:PlainSink):String {
        return "plain";
    }
}

class NonSharedEscapingForwardOps {
    public static function run():String {
        final worker = new PlainWorker();
        final sink:PlainSink = worker;
        return sink.run() + ":" + worker.run();
    }
}
#end
