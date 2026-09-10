package boring;

class IterItem {
    public var index:Int;
    public function new(index:Int) {
        this.index = index;
    }
}

class IterPrep {
    public var items:Array<IterItem>;
    public function new(items:Array<IterItem>) {
        this.items = items;
    }
}

class RustIterOps {
    public static function sumItems(prep:IterPrep):Int {
        var total = 0;
        for (item in prep.items) {
            total += item.index;
        }
        return total;
    }
}
