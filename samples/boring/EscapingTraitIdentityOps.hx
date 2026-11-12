package boring;

#if rust_output
/**
    Live reproduction fixture for the EscapingTraitImplFailClosed dead path
    (docs/compiler-policy-interfaces.md). Three trigger paths for a trait
    method whose body needs handle identity:

    A. The method forwards "this" to a handle-taking static callee.
    B. The method calls another escaping method on "this" (transitive).
    C. Both triggers appear in one method body.

    The interface is @:sharedHandle, so interface slots lower to
    Rc<RefCell<dyn Trait>> and a call through the slot dispatches into the
    struct trait impl -- the fail-closed panic body. Direct calls on the
    concrete handle stay on the NonTraitMethodFullBody path and keep
    working, which is the concrete-vs-trait contrast the adapter task
    needs as its live evidence.
*/
@:sharedHandle
interface EscapingSink {
    function runA():String;
    function runB():String;
    function runC():String;
}

class EscapingHost {
    public function new() {}

    public function describe():String {
        return "host";
    }
}

class EscapingWorkerA implements EscapingSink {
    public function new() {}

    // Handle-taking static callee: the parameter is a plain-class handle
    // slot, so a body forwarding "this" here needs handle identity.
    public static function forward(host:EscapingWorkerA):String {
        return "a:" + host.describe();
    }

    public function describe():String {
        return "host";
    }

    // Path A: direct forward of "this" to the handle-taking static.
    public function runA():String {
        return "a:" + EscapingWorkerA.forward(this);
    }

    public function runB():String {
        return "a-unused";
    }

    public function runC():String {
        return "a-unused";
    }
}

class EscapingWorkerB implements EscapingSink {
    public function new() {}

    public static function forward(host:EscapingWorkerB):String {
        return host.describe();
    }

    public function describe():String {
        return "host";
    }

    // Path B: runA forwards "this" by calling runB on it, and runB
    // escapes -- so runA escapes transitively.
    public function runA():String {
        return "b:" + this.runB();
    }

    public function runB():String {
        return EscapingWorkerB.forward(this);
    }

    public function runC():String {
        return "b-unused";
    }
}

class EscapingWorkerC implements EscapingSink {
    public function new() {}

    public static function forward(host:EscapingWorkerC):String {
        return host.describe();
    }

    public function describe():String {
        return "host";
    }

    public function runA():String {
        return "c-a:" + EscapingWorkerC.forward(this);
    }

    public function runB():String {
        return "c-b:" + this.runA();
    }

    // Path C: both triggers -- static forward AND escaping this-call --
    // inside one method body.
    public function runC():String {
        return "c-c:" + EscapingWorkerC.forward(this) + "|" + this.runA();
    }
}

class EscapingTraitIdentityOps {
    // Concrete-handle path: direct calls on the concrete class lower the
    // full body on the handle (NonTraitMethodFullBody) and stay correct.
    public static function concreteDirectA():String {
        final worker:EscapingWorkerA = new EscapingWorkerA();
        return worker.runA();
    }

    public static function concreteDirectB():String {
        final worker:EscapingWorkerB = new EscapingWorkerB();
        return worker.runB();
    }

    public static function concreteDirectC():String {
        final worker:EscapingWorkerC = new EscapingWorkerC();
        return worker.runC();
    }

    // Trait-object path: a call through the @:sharedHandle slot dispatches
    // into the struct trait impl, whose body is the fail-closed panic.
    // These are the live-reproduction entry points for the Rust-side
    // should_panic test; the Haxe-side test suite never calls them.
    public static function throughSinkA():String {
        final sink:EscapingSink = new EscapingWorkerA();
        return sink.runA();
    }

    public static function throughSinkB():String {
        final sink:EscapingSink = new EscapingWorkerB();
        return sink.runB();
    }

    public static function throughSinkC():String {
        final sink:EscapingSink = new EscapingWorkerC();
        return sink.runC();
    }
}
#else
class EscapingTraitIdentityOps {}
#end
