package boring;

#if rust_output
/**
    An owned boundary that receives the borrowed `self` receiver. Every method
    is emitted with a borrowed receiver, so a constructor argument or a
    conditional arm that reads it must clone the referent at the owned value
    boundary. The named borrowedReceiver rule covers each site.
*/
private class BorrowedReceiverState {
    public final owner:BorrowedReceiverHolder;

    public function new(owner:BorrowedReceiverHolder) {
        this.owner = owner;
    }
}

private class BorrowedReceiverHolder {
    public final label:String;

    public function new(label:String) {
        this.label = label;
    }

    public function snapshot():BorrowedReceiverState {
        return new BorrowedReceiverState(this);
    }

    public function pick(flag:Bool):BorrowedReceiverHolder {
        return if (flag) this else new BorrowedReceiverHolder("other");
    }
}

class BorrowedReceiverBoundaryOps {
    public static function snapshotLabel():String {
        final holder = new BorrowedReceiverHolder("root");
        return holder.snapshot().owner.label;
    }

    public static function pickLabel(flag:Bool):String {
        final holder = new BorrowedReceiverHolder("root");
        return holder.pick(flag).label;
    }
}
#else
class BorrowedReceiverBoundaryOps {}
#end
