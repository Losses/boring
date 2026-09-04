package tests;

// Shared helpers for HandWrittenLoopPositionTests. Test classes carry
// test functions and nothing else (feature spec 27), so the hand-written
// accumulation loops live here as members of an ordinary class.
class HandWrittenLoopPositionSupport {
    public static function accumulate(values:Array<Int>):Array<Int> {
        final result = new Array<Int>();
        for (index in 0...values.length)
            result.push(values[index] + 1);
        return result;
    }

    public static function nestedIf(values:Array<Int>):Array<Int> {
        final result = new Array<Int>();
        if (values.length > 0) {
            final inner = new Array<Int>();
            for (index in 0...values.length)
                inner.push(values[index] + 1);
            for (value in inner)
                result.push(value);
        }
        return result;
    }

    public static function nestedWhile(values:Array<Int>):Array<Int> {
        final result = new Array<Int>();
        var pass = 0;
        while (pass < 1) {
            final inner = new Array<Int>();
            for (index in 0...values.length)
                inner.push(values[index] + 1);
            for (value in inner)
                result.push(value);
            pass++;
        }
        return result;
    }

    public static function outerLoop(values:Array<Int>):Array<Int> {
        final result = new Array<Int>();
        for (pass in 0...2) {
            final inner = new Array<Int>();
            for (index in 0...values.length)
                inner.push(values[index] + 1);
            for (value in inner)
                result.push(value);
        }
        return result;
    }
}
