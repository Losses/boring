package org.tiqian.protocol;

/**
 * The weight selector one face carries into face selection: an explicit
 * contiguous range (variable font) or a single resolved weight (static
 * font). Mirrors the Rust FontWeightSpec: Range(f64, f64) and
 * Single(Option<f64>). Number-coercion quirks of other array shapes
 * live at the Neon boundary, so only these two constructors exist here.
 *
 * The generated Rust is a struct variant (Range { min, max }), not the
 * tuple variant the handwritten shell used; the lowering step adapts call
 * sites without any byte-layout change, since the selection keys serialize
 * the payload values rather than the enum memory layout.
 */
enum FontWeightSpec {
    Range(min:Float, max:Float);
    Single(value:Null<Float>);
}
