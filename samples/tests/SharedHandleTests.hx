package tests;

import std.Test;

/**
    A stateful interface: the implementor carries a private mutable field,
    so every binding that names the implementor must observe the same
    updates (ClassHandleShare). The Rust lowering registers this interface
    in RustDecl.sharedInterfaces, which lowers its interface slots to
    Arc<Mutex<dyn ..>> handles instead of owning Box clones.
**/
interface ISharedHandleCounter {
    function bump():Void;
    function count():Int;
}

/**
    The minimal shared-state implementor: one private mutable field.
**/
class TotalSharedHandleCounter implements ISharedHandleCounter {
    var n:Int = 0;

    public function new() {}

    public function bump():Void {
        n = n + 1;
    }

    public function count():Int {
        return n;
    }
}

/**
    A consumer that receives the implementor through interface slots: one
    non-null slot and one nullable slot, the two slot shapes the emitter
    lowers differently (RustExpr.hx ClassHandleShare sites).
**/
class SharedHandleConsumer {
    var store:ISharedHandleCounter;
    var optStore:Null<ISharedHandleCounter>;

    public function new(store:ISharedHandleCounter, optStore:Null<ISharedHandleCounter>) {
        this.store = store;
        this.optStore = optStore;
    }

    public function bumpThroughSlots():Void {
        store.bump();
        if (optStore != null)
            optStore.bump();
    }
}

class SharedHandleTests {
    @:test("an implementor handed through an interface slot stays one object")
    public static function interfaceSlotSharesState():Void {
        final counter = new TotalSharedHandleCounter();
        final consumer = new SharedHandleConsumer(counter, null);
        consumer.bumpThroughSlots();
        consumer.bumpThroughSlots();
        Test.equals(2, counter.count(), "writes through the slot must reach the source binding");
    }

    @:test("an implementor handed through a nullable interface slot stays one object")
    public static function nullableSlotSharesState():Void {
        final counter = new TotalSharedHandleCounter();
        final consumer = new SharedHandleConsumer(counter, counter);
        consumer.bumpThroughSlots();
        consumer.bumpThroughSlots();
        Test.equals(4, counter.count(), "both slots must name the same object as the source binding");
    }
}
