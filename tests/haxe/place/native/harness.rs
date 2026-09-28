//! Native harness for the generated place crate.
//!
//! The harness calls the generated public entry points and prints phase
//! markers around them. It implements no source operation and contains no
//! expectation about the generated behavior.

fn main() {
    println!("[native] start");
    placegen::place::place_observe_static::PlaceObserveStatic::new().run();
    println!("[native] end");
}
