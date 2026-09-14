package boring;

#if rust_output
import std.ReadOnlyArray;

/**
    An owned Vec boundary that receives a borrowed array parameter. An
    ordinary Array<T> parameter lowers to a &Vec<T> view whose storage stays
    with the caller, while a nullable field, a nullable return, and an owned
    assignment target own their Vec. The named borrowedArrayRead rule clones
    the referent once at each of those boundaries.
*/
private class BorrowedArrayHolder {
    public final values:Null<Array<Int>>;

    public function new(values:Null<Array<Int>>) {
        this.values = values;
    }

    public function hasValues():Bool {
        return this.values != null;
    }
}

private class BorrowedReadOnlyArrayHolder {
    public final values:Null<ReadOnlyArray<Int>>;

    public function new(values:Null<ReadOnlyArray<Int>>) {
        this.values = values;
    }

    public function hasValues():Bool {
        return this.values != null;
    }
}

class BorrowedArrayBoundaryOps {
    public static function wrap(values:Array<Int>):BorrowedArrayHolder {
        return new BorrowedArrayHolder(values);
    }

    public static function readOnlyWrap(values:Array<Int>):BorrowedReadOnlyArrayHolder {
        return new BorrowedReadOnlyArrayHolder(values);
    }

    public static function nullableReturn(values:Array<Int>):Null<Array<Int>> {
        return values;
    }

    public static function rebind(values:Array<Int>):Int {
        var current = [0];
        current = values;
        return current.length;
    }
}
#else
class BorrowedArrayBoundaryOps {}
#end
