import SemanticPolicy.RepresentationRole;

/**
    The Rust target realization profile (policy entry P-25). This module is the
    single place a concrete Rust spelling lives: an abstract role plus its
    Send/Sync constraint map to a concrete Rust type. SemanticPolicy.decide() is
    target-neutral and never references this module; a Kotlin/Swift profile is a
    separate table that also never touches decide(). SemanticPolicy itself
    contains no Rust spelling literal: the spelling is generated here.

    Adding a role changes exactly this switch and the RepresentationRole enum,
    nothing else (structural assertion, P-22): the switch is exhaustive over
    RepresentationRole, so a role without a case is a compile error.

    P-16 (fixed to the B-line census, three targets at 0 errors): a cross-thread
    shared handle (@:sharedHandle, isCrossThreadShared) is
    Arc<Mutex<dyn Trait + Send + Sync>> (the Send/Sync bound is forced by E0277);
    the single-thread shared handle stays Rc<RefCell<dyn Trait>>. The one
    semantic fact isCrossThreadShared decides the two spellings.

    Fail-closed: a null/unknown role throws immediately at generation time. It
    is never returned as a string and never rendered into a product, so a bad
    plan cannot silently produce bad Rust or defer the failure to cargo (where
    the planKey context would be lost). The wiring wraps this throw with the
    planKey. A runtime test asserts that spell(null) throws.
**/
class RustAbiProfile {
    public static function spell(role:Null<RepresentationRole>, sendSync:Bool):String {
        return switch (role) {
            case null: throw "RustAbiProfile.spell: unknown role (null) - fail-closed, never rendered";
            case RepresentationRole.Value: "T";
            case RepresentationRole.ClassHandle: "Rc<RefCell<C>>";
            case RepresentationRole.TraitHandle: sendSync ? "Arc<Mutex<dyn Trait + Send + Sync>>" : "Rc<RefCell<dyn Trait>>";
            case RepresentationRole.AdapterHandle: "AdapterHandle(C,I)";
            case RepresentationRole.TraitHandleAdapter: "XxxAdapter{ object: Rc<RefCell<C>> }";
            case RepresentationRole.ReadBorrow: "&T";
            case RepresentationRole.WriteBorrow: "&mut T";
        };
    }
}
