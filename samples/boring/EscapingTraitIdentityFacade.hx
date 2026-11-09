package boring;

#if rust_output
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
}
#else
class EscapingTraitIdentityFacade {}
#end
