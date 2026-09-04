package boring;

import std.ReadOnlyArray;

/** Collection fields use the Std.string array lowering (feature 33). */
@:dataClass
class PrintedCollection {
    public final names:ReadOnlyArray<String>;
    public final counts:Array<Int>;
    public final points:ReadOnlyArray<PrintedPoint>;
    public final matrix:Array<Array<Int>>;
    public final none:Array<String>;

    public function new(names:ReadOnlyArray<String>, counts:Array<Int>, points:ReadOnlyArray<PrintedPoint>, matrix:Array<Array<Int>>, none:Array<String>) {
        this.names = names;
        this.counts = counts;
        this.points = points;
        this.matrix = matrix;
        this.none = none;
    }
}

/**
 * A payload enum element of a collection field (features 34 and 42). The
 * member carries the labeled renderer inside the array loop, so the loop
 * body holds calls only.
 */
@:dataClass
class PrintedEnumCollection {
    public final flags:ReadOnlyArray<PrintedFlag>;

    public function new(flags:ReadOnlyArray<PrintedFlag>) {
        this.flags = flags;
    }
}

@:dataClass
class PrintedPoint {
    public final x:Int;
    public final y:Int;

    public function new(x:Int, y:Int) {
        this.x = x;
        this.y = y;
    }
}

/**
 * A nullable collection field (feature spec 33 ruling 4 gap closure): the
 * printed member renders null as "null" and a present array through the
 * ruled array form.
 */
@:dataClass
class PrintedNullableCollection {
    public var words:Null<ReadOnlyArray<String>>;

    public function new(words:Null<ReadOnlyArray<String>>) {
        this.words = words;
    }
}

enum PrintedFlag {
    Silent;
    Steps(count:Int);
}
