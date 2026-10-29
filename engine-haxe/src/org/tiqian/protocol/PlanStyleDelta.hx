package org.tiqian.protocol;

/**
 * The paint-relevant per-cell style delta (PreparedParagraph.kt:261-274).
 * Only the three paint fields can differ from the paragraph base style; a
 * field that matches the base is absent (null) so an all-default delta still
 * serialises as an empty object `{}` and marks the cluster as non-default.
 * The Rust reader keeps this object parsed (plan.rs:183) and replays its
 * members the way js reads `cell.style`.
 */
typedef PlanStyleDelta = {
    var fontSize:Null<Float>;
    var fontWeight:Null<Int>;
    var italic:Null<Bool>;
}