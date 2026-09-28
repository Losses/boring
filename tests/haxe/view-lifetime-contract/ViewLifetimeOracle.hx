import std.ReadOnlyArray;

class ViewLifetimeOracle {
    /** Case 1: the source binding is reassigned to another array after the conversion. */
    public static function rebind():Int {
        var values:Array<Int> = [1, 2, 3];
        final view:ReadOnlyArray<Int> = values;
        values = [9, 8, 7];
        return view[0] * 100 + view[1] * 10 + view[2];
    }

    /** Case 2, producer side: the local scope ends and the conversion happens at return. */
    public static function escapedProducer():ReadOnlyArray<Int> {
        var values:Array<Int> = [5, 6];
        return values;
    }

    /** Case 2, consumer side: the view outlives the producer's local scope. */
    public static function escapedConsumer():Int {
        final view = escapedProducer();
        return view[0] * 10 + view[1];
    }

    /** Sharing discriminator, local: a retained mutable alias mutates the original container. */
    public static function localAliasMutation():Int {
        var values:Array<Int> = [1];
        final view:ReadOnlyArray<Int> = values;
        values[0] = 42;
        return view[0];
    }

    /** Case 3, producer side: rebind to a replacement and mutate the replacement. */
    public static function combinedProducer():ReadOnlyArray<Int> {
        var values:Array<Int> = [1, 2, 3];
        final view:ReadOnlyArray<Int> = values;
        values = [9, 8, 7];
        values[0] = 77;
        return view;
    }

    /** Case 3, consumer side: the view still observes the original container. */
    public static function combinedConsumer():Int {
        final view = combinedProducer();
        return view[0] * 100 + view[1] * 10 + view[2];
    }

    /**
        Cross-boundary discriminator: the producer returns the view together
        with an ordinary holder retaining a mutable alias to the ORIGINAL
        container; the replacement container is rebound and mutated inside
        the producer before the return.
    **/
    public static function boundaryProducer():ViewLifetimeBoundaryResult {
        var values:Array<Int> = [5, 6, 4];
        final original:ViewLifetimeHolder = new ViewLifetimeHolder(values);
        final view:ReadOnlyArray<Int> = values;
        values = [9, 8, 7];
        values[0] = 77;
        return new ViewLifetimeBoundaryResult(view, original);
    }

    /** After the producer's scope has ended, the retained alias mutates the original; the replacement mutation stays out of the view. */
    public static function boundaryProbe():String {
        final result = boundaryProducer();
        final before = result.view[0] * 100 + result.view[1] * 10 + result.view[2];
        result.holder.values[1] = 99;
        final after = result.view[0] * 100 + result.view[1] * 10 + result.view[2];
        return before + ":" + after;
    }

    public static function main():Void {
        #if !swift_output
        std.Console.log("rebind=" + rebind());
        std.Console.log("escaped=" + escapedConsumer());
        std.Console.log("local-mutation=" + localAliasMutation());
        std.Console.log("combined=" + combinedConsumer());
        std.Console.log("boundary=" + boundaryProbe());
        #else
        rebind();
        escapedConsumer();
        localAliasMutation();
        combinedConsumer();
        boundaryProbe();
        #end
    }
}
