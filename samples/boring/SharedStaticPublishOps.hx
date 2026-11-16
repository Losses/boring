package boring;

#if rust_output
/**
    A shared static table grown from a local builder and published in one
    assignment. The rejected shape reads the table tail and appends to the
    shared static, which takes the lock twice; the samples had no shared static
    that a reader can observe while it grows.
**/
class SharedStaticPublishOps {
    static var table:Array<Int> = [];

    static function buildTable(k:Int):Array<Int> {
        final built:Array<Int> = [1];
        while (built.length <= k)
            built.push(built[built.length - 1] * 3);
        return built;
    }

    public static function valueAt(k:Int):Int {
        if (table.length <= k)
            table = buildTable(k);
        return table[k];
    }

    public static function reset():Void {
        table = [1];
    }

    public static function peek(k:Int):Int
        return table[k];
}
#else
class SharedStaticPublishOps {}
#end
