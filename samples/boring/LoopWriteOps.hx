package boring;

class LoopWriteOps {
    public static function tailIncrement(n:Int):Int {
        var total = 0;
        var i = 1;
        var bound = n;
        while (i < bound) {
            total += i;
            i += 1;
        }
        return total;
    }

    public static function branchIncrement(n:Int):Int {
        var total = 0;
        var i = 1;
        var bound = n;
        while (i < bound) {
            total += i;
            if (i == 2)
                i++;
            i += 1;
        }
        return total;
    }

    public static function nonUnitIncrement(n:Int):Int {
        var total = 0;
        var i = 1;
        var bound = n;
        while (i < bound) {
            total += i;
            i += 2;
        }
        return total;
    }

    public static function closureIncrement(n:Int):Int {
        var total = 0;
        var i = 1;
        var bound = n;
        var advance = function() {
            i++;
        };
        while (i < bound) {
            total += i;
            advance();
            i += 1;
        }
        return total;
    }
}
