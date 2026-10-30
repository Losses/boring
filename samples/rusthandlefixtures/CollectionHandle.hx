package rusthandlefixtures;

// collection: an Array of handles iterated and dispatched.
class Cell {
    public var label:String;
    public function new(label:String) {
        this.label = label;
    }

    public function text():String {
        return label;
    }
}

class CollectionHandleOps {
    public static function run():String {
        final cells:Array<Cell> = [new Cell("a"), new Cell("b")];
        var out = "";
        for (cell in cells) {
            out += cell.text();
        }
        return out;
    }
}
