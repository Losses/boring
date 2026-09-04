package boring;

import std.ReadOnlyArray;

class ArrayIterationOps {
    public static function sumValues(values:Array<Int>):Int {
        var total = 0;
        for (item in values) {
            total += item;
        }
        return total;
    }

    public static function countReadOnly(values:ReadOnlyArray<Int>):Int {
        var total = 0;
        for (item in values) {
            total += item;
        }
        return total;
    }

    public static function sumField(holder:Holder):Int {
        var total = 0;
        for (item in holder.values) {
            total += item;
        }
        return total;
    }
}

class Holder {
    public final values:Array<Int>;

    public function new(values:Array<Int>) {
        this.values = values;
    }
}
