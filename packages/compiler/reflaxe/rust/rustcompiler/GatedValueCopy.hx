package rustcompiler;

/**
    The single judgment for "is this rendered text a value copy of a
    gated class?" -- shared by the value-slot coercion
    (renderValueForType) and the coalescing-default wrap so the two sites
    can never drift apart.

    Rules, by rendered text:
    - "Rc::clone(&x)"              -> false: a handle clone shares the cell.
    - "X::new()" (handle-ABI ctor) -> false: the constructor returns the
      Rc<RefCell<Self>> handle itself.
    - "Rc::new(RefCell::new(x))"   -> false: an already-wrapped slot.
    - anything else, including the empty string -> true, failing closed:
      we cannot prove the text is a handle, and a silent double-wrap is
      worse than a hard error. (TraitIdentityAdapter)

    Pure string logic, no macro context: the tests/haxe
    rust-gated-value-copy assertions compile and run it standalone.
*/
class GatedValueCopy {
    /** Whether the rendered text names a handle (clone, constructor or an
        already-wrapped slot). */
    public static function renderedIsHandleForm(rendered:String):Bool {
        if (rendered == null || rendered == "")
            return false;
        return StringTools.startsWith(rendered, "Rc::clone(&")
            || StringTools.startsWith(rendered, "Rc::new(RefCell::new(")
            || rendered.indexOf("::new(") >= 0;
    }

    /** The named judgment. `gated` is the caller's ABI verdict for the
        class (RustDecl.usesHandleIdentity): only gated classes can
        produce a value copy, and only when the text is not already a
        handle form. Empty/unknown text fails closed. */
    public static function isValueCopy(gated:Bool, rendered:String):Bool {
        return gated && !renderedIsHandleForm(rendered);
    }
}
