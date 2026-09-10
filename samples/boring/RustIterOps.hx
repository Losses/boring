package boring;

import std.SortedMap;

class RustIterOps {
    public static function iterMapValues(map:SortedMap<String, Int>):Int {
        var total = 0;
        for (v in map) {
            total += v;
        }
        return total;
    }

    public static function filterAndCollect(values:Array<Int>):Array<Int> {
        var result:Array<Int> = [];
        for (v in values) {
            if (v > 0) {
                result.push(v);
            }
        }
        return result;
    }

    public static function spliceAndShift(arr:Array<Int>):Array<Int> {
        arr.splice(0, 1);
        arr.push(42);
        return arr;
    }

    public static function optionalFieldCtor(opt:Null<Int>):OptionalHolder {
        return new OptionalHolder(opt);
    }

    public static function matchArmIter(items:Array<Int>):Int {
        var total = 0;
        var maybeArr:Null<Array<Int>> = items;
        switch (maybeArr) {
            case Some(arr):
                for (v in arr) {
                    total += v;
                }
            case None:
        }
        return total;
    }
}

class OptionalHolder {
    public final value:Int;
    public final extra:Null<Int>;

    public function new(value:Int, extra:Null<Int> = null) {
        this.value = value;
        this.extra = extra;
    }
}
