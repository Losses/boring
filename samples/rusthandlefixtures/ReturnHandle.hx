package rusthandlefixtures;

// return handle: a function returns a freshly constructed handle.
class Item {
    public function new() {}
}

class ReturnHandleOps {
    public static function make():Item {
        return new Item();
    }
}
