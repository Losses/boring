package boring;

/**
    An interface method that writes a receiver field forces the mutable
    receiver form on the trait and on every implementation. The shape is
    the union over the implementations: a read-only implementation keeps
    the mutable form that an earlier writing implementation established.
*/
interface MutatingCounter {
    function bump():Int;
}

class MutatingCounterOps {
    static function makeCounter():MutatingCounter {
        return new CountingMutatingCounter();
    }

    public static function bumpTwice():Int {
        var counter = makeCounter();
        return counter.bump() + counter.bump();
    }

    static function makeReadOnlyCounter():MutatingCounter {
        return new ReadOnlyMutatingCounter();
    }

    public static function readOnly():Int {
        var counter = makeReadOnlyCounter();
        return counter.bump();
    }

    public static function bumpThriceConcrete():Int {
        final counter = new CountingMutatingCounter();
        counter.bump();
        counter.bump();
        return counter.bump();
    }
}

class CountingMutatingCounter implements MutatingCounter {
    public var count:Int = 0;

    public function new() {}

    public function bump():Int {
        count += 1;
        return count;
    }
}

class ReadOnlyMutatingCounter implements MutatingCounter {
    public function new() {}

    public function bump():Int {
        return 0;
    }
}
