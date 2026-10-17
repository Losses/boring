class EmptyDefaultOnly {
    public static function observedValue():Int {
        final ro = new ReadOnlyHolder();
        final mut = new MutableHolder();
        return 10 + ro.count() + mut.count();
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

class MutableHolder {
    final values:Array<Int>;

    public function new(?values:Array<Int>) {
        this.values = values == null ? [] : values;
    }

    public function count():Int {
        return values.length;
    }
}
