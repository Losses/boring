package boring;

#if rust_output
/** A non-null member whose fields sit one step below a guarded local. **/
class NullGuardNestedSpan {
    public final left:Float;
    public final right:Float;

    public function new(left:Float, right:Float) {
        this.left = left;
        this.right = right;
    }
}

/** A holder whose member is itself never null. **/
class NullGuardNestedHolder {
    public final span:NullGuardNestedSpan;

    public function new(span:NullGuardNestedSpan) {
        this.span = span;
    }
}

/**
    A null guard narrows a local, and a read below that local continues
    through a non-null member. The binding stands in for the local, so the
    intermediate member stays on the rendered access path. A read with the
    guarded local as the complete subject keeps its existing lowering.
*/
class NullGuardNestedFieldOps {
    public static function startsBefore(holder:Null<NullGuardNestedHolder>, end:Float):Bool {
        return holder != null && holder.span.left < end;
    }

    public static function matchingSpan(holder:Null<NullGuardNestedHolder>, other:NullGuardNestedHolder):Bool {
        if (holder != null && holder.span.left == other.span.left)
            return true;
        return false;
    }

    public static function spanLeft(holder:Null<NullGuardNestedHolder>):Float {
        if (holder != null && holder.span.left < 10.0)
            return holder.span.left;
        return 0.0;
    }
}
#else
class NullGuardNestedFieldOps {}
#end
