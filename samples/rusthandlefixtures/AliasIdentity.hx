package rusthandlefixtures;

// alias identity: two variables alias the same handle; mutating through one
// must be visible through the other (Rc clone, never a value copy).
class Box {
    public var value:Int;
    public function new(value:Int) {
        this.value = value;
    }
}

class AliasIdentityOps {
    public static function run():Int {
        final first = new Box(1);
        final second = first;
        second.value = 2;
        return first.value;
    }
}
