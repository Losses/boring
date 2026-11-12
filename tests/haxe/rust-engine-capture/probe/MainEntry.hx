package probe;

/**
    Non-test main entry. It MUST call Engine.makeCapture so the generator does
    not dead-code-eliminate the Engine class and its capture path.

    A fixture whose green comes from dead-code elimination is worse than no
    test: it makes a path look verified when it was never compiled. entry()
    therefore constructs an Engine, builds the function value, and invokes it,
    forcing the generated Rust to compile the Rc<RefCell<Engine>> handle and
    the Rc::clone capture.

    Reverse assertion (encoded in the Haxe source):
      - correct emitter  -> param Rc<RefCell<Engine>>, closure captures Rc::clone
                           -> cargo build GREEN.
      - degraded emitter -> param bare &mut Engine / &Engine, the 'static
                           function value cannot capture a borrow
                           -> cargo build RED.
**/
class MainEntry {
    public static function entry():Int {
        final engine = new Engine();
        final fn = Engine.makeCapture(engine);
        return fn(1);
    }
}
