package probe;

/**
    Minimal reproducer for the engine 'static-closure capture ABI (TCN-302).

    Mirrors the tiqian pattern: a plain class (Engine) with a non-Clone field
    (a Box<dyn Trait> interface slot) is passed as a parameter to a static
    function that builds a function value capturing the engine by value.

    Per the Target Semantic Policy (P-24 / ClassParamHandle), the engine must
    lower to an Rc<RefCell<Engine>> handle, so the closure captures Rc::clone
    (cheap, alias-preserving) and the generated Rust compiles clean. A bare
    &mut Engine / &Engine lowering (the pre-B6 defect) cannot be captured into
    a function value and fails to compile.
**/
interface IService {
    function serve():Int;
}

class StubService implements IService {
    public function new() {}
    public function serve():Int { return 1; }
}

class Engine {
    public final service:IService;

    public function new(?service:IService) {
        this.service = service == null ? new StubService() : service;
    }

    /** A function value that captures the engine by value (Rc::clone). */
    public static function makeCapture(engine:Engine):Int->Int {
        return function(x:Int):Int {
            return x + engine.service.serve();
        };
    }
}
