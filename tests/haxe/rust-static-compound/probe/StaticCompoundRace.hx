package probe;

// The pre-fix shape: a shared static mutex-backed array grown by reading its
// tail and appending to it. Each access takes the lock on its own, so two
// threads can interleave the read and the append and the entries stop
// matching their indices.
class StaticCompoundRace {
    static var table:Array<Int> = [];

    // A deliberately wide window between the tail read and the append, so the
    // interleaving shows up in a short test run.
    static function scale(value:Int, factor:Int):Int {
        var acc = 0;
        var step = 0;
        while (step < 4000) {
            acc = (acc + step) % 13;
            step++;
        }
        return value * factor + (acc - acc);
    }

    public static function reset():Void {
        table = [1];
    }

    public static function peek(k:Int):Int {
        return table[k];
    }

    public static function valueAt(k:Int):Int {
        if (table.length == 0)
            table = [1];
        if (k < table.length)
            return table[k];
        var last = table[table.length - 1];
        var i = table.length - 1;
        while (i < k) {
            last = scale(last, 3);
            i++;
            table.push(last);
        }
        return last;
    }
}
