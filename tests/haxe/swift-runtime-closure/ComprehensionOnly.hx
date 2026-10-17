class ComprehensionOnly {
    public static function observedValue():Int {
        final filled = [for (i in 0...5) i * 2];
        var sum = 0;
        for (v in filled) sum += v;
        return sum + filled.length;
    }

    static function main():Void {}
}
