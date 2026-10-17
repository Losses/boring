class SliceOnly {
    public static function observedValue():Int {
        final values = [0, 1, 2, 3, 4, 5];
        final sliced = values.slice(1, 4);
        var sum = 0;
        for (v in sliced) sum += v;
        return sum + sliced.length;
    }

    static function main():Void {}
}
