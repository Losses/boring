//! Native invocation harness for the Rust generated crate of the signed key
//! composition fixture. The runner compiles the generated tree as a library
//! and links this harness against it through `--extern`, so the harness
//! prints the text one generated observation function returns. It holds no
//! ordering decision and re-implements no comparator. The case name is the
//! first program argument.

use keycomp::composition::KeyCompositionObserve;

fn observation(name: &str) -> Option<String> {
    match name {
        "direct-int" => Some(KeyCompositionObserve::key_composition_observe_direct_int().to_utf8_lossy()),
        "direct-int-extremes" => Some(
            KeyCompositionObserve::key_composition_observe_direct_int_extremes().to_utf8_lossy(),
        ),
        "typedef-int" => Some(KeyCompositionObserve::key_composition_observe_typedef_int().to_utf8_lossy()),
        "typedef-int-extremes" => Some(
            KeyCompositionObserve::key_composition_observe_typedef_int_extremes().to_utf8_lossy(),
        ),
        "composite-nullable" => Some(
            KeyCompositionObserve::key_composition_observe_composite_nullable().to_utf8_lossy(),
        ),
        "composite-extremes" => Some(
            KeyCompositionObserve::key_composition_observe_composite_extremes().to_utf8_lossy(),
        ),
        _ => None,
    }
}

fn main() {
    let requested = std::env::args().nth(1);
    let requested = requested.unwrap_or_else(|| String::from("<none>"));
    match observation(requested.as_str()) {
        Some(text) => println!("{}", text),
        None => {
            eprintln!("signed-key-composition harness: unknown case {}", requested);
            std::process::exit(2);
        }
    }
}
