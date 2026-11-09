package boring;

#if rust_output
import boring.EscapingTraitIdentityOps.EscapingWorkerA;
/**
    Non-test referencer keeping boring.EscapingTraitIdentityOps out of the
    test reclassification (and its #![cfg(test)] gate), so the Rust
    integration test tests/rust/escaping_trait.rs can reach the fail-closed
    panic path. (TraitIdentityAdapter)
*/
class EscapingTraitIdentityFacade {
    public function new() {}

    public function concreteA():String {
        return EscapingTraitIdentityOps.concreteDirectA();
    }

    public function sinkC():String {
        return EscapingTraitIdentityOps.throughSinkC();
    }

    // Drives the value-slot coercion for a gated class: proves the
    // emission check fires (and then that the single-unsizing bind
    // compiles) instead of double-wrapping silently.
    public function consume(w:EscapingWorkerA):String {
        return w.runA();
    }

    public function produceAndConsume():String {
        return consume(new EscapingWorkerA());
    }

    public function pickOrDefault(?w:EscapingWorkerA):String {
        final worker = w == null ? new EscapingWorkerA() : w;
        return worker.runA();
    }
}
#else
class EscapingTraitIdentityFacade {}
#end
