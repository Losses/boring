package boring;

/** Boundary shapes for the shared counted-loop recognition contract. */
class IntervalSurfaceOps {
    public static function doWhileTrip():Int {
        var i = 1;
        var trips = 0;
        do {
            var captured = i++;
            trips += 1;
        } while (i < 0);
        return trips;
    }

    public static function nullableCounter():Int {
        var i:Null<Int> = null;
        var trips = 0;
        while (i < 3) {
            var captured = i++;
            trips += 1;
        }
        return trips;
    }

    public static function parenthesizedCounter():Int {
        var i = 0;
        while (((i)) < 3) {
            var captured = i++;
        }
        return i;
    }

    public static function castCounter():Int {
        var i = 0;
        while (cast(i, Int) < 3) {
            var captured = i++;
        }
        return i;
    }
}
