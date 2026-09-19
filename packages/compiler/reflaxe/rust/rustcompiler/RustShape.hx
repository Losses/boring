package rustcompiler;

/**
 * Exact Option-shape parser over rendered Rust text.
 *
 * The type account of this target is the rendered text itself: every gate
 * that must decide "does this expression evaluate to an Option-shaped
 * value or a bare value" reads the same text through this same parser, so
 * no two boundaries can disagree about one expression. The parser answers
 * one question only (Option vs bare); numeric domains and borrow shapes
 * stay with their own mechanisms.
 *
 * Unknown is a legitimate answer: identifiers, field reads, and index
 * reads carry no shape in their text. Callers fall back to the typed
 * expression structure for those forms.
 *
 * (ShapeParse)
 */
enum RustShape {
    ShapeOption;
    ShapeBare;
    /** Composite whose arms disagree (an if/match with a bare arm and an
        Option arm). Boundaries must not adapt a mixed text; the renderer
        unifies the arms instead. */
    ShapeMixed;
    ShapeUnknown;
}
