package rusthandlefixtures;

// handle field read: extract a handle field from a borrowed owner.
// Mirrors tiqian line_adjustment_stage.rs:899 ((prep.borrow().input).clone()).
class Inner {
    public function new() {}
}

class Outer {
    public final inner:Inner;
    public function new(inner:Inner) {
        this.inner = inner;
    }
}

class HandleFieldReadOps {
    public static function extract(outer:Outer):Inner {
        return outer.inner;
    }
}
