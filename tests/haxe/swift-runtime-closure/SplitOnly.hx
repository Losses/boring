class SplitOnly {
    public static function observedValue():Int {
        final parts = "a-b-c".split("-");
        var total = 0;
        for (p in parts) total += p.length;
        return parts.length * 10 + total;
    }

    static function main():Void {}
}
