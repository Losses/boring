#if (macro || reflaxe_runtime)
import haxe.macro.Context;

/**
    Configures the Rust target's sealed-interface downcast lowering
    (feature spec 32 amendment: trait-object field routing). A sealed
    interface's `Std.isOfType(x, Variant)` guard followed by
    `cast(x, Variant).field` needs the trait object narrowed to the
    concrete variant before the field read; without the lowering the
    generated `Box<dyn Trait>.field` does not compile (E0609).

    The lowering is on by default because a sealed interface's implementor
    set is closed and in-program, so the `as_any` hook and `downcast_ref`
    are always sound. A compilation that never downcasts a sealed
    interface can opt out with `-D no-interface-downcast` to keep the
    trait free of the `as_any` hook and the `std::any::Any` dependency.
**/
class InterfaceDowncast {
    /** True when the Rust target lowers sealed-interface downcasts. */
    public static function enabled():Bool {
        return !Context.defined("no-interface-downcast");
    }
}
#end