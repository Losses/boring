class BoundaryOnly {
    public static function observedValue():Int {
        final ro = new ReadOnlyHolder();
        final view:std.ReadOnlyArray<Int> = [1, 2, 3];
        final total = traverse(view);
        return 100 + ro.count() + total + view.length;
    }

    static function traverse(values:std.ReadOnlyArray<Int>):Int {
        var total = 0;
        for (index in 0...values.length) {
            total += values[index];
        }
        return total;
    }

    static function main():Void {}
}

class ReadOnlyHolder {
    final values:std.ReadOnlyArray<Int>;

    public function new(?values:std.ReadOnlyArray<Int>) {
        this.values = values == null ? [] : values;
    }

    public function count():Int {
        return values.length;
    }
}
