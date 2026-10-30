package rusthandlefixtures;

// Self rewrap: an instance method passes 'this' as a handle argument to a
// static function. Mirrors tiqian paragraph_layout_engine.rs:284-300
// (Rc::new(RefCell::new(self.clone())) forbidden pattern).
class SelfRewrap {
    public function new() {}

    public static function identity(engine:SelfRewrap):Int {
        return 1;
    }

    public function run():Int {
        return SelfRewrap.identity(this);
    }
}
