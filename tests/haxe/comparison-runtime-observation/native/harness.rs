//! Native invocation harness for the Rust generated crate of the comparison
//! observation fixture. The runner compiles the generated tree as a library and
//! links this harness against it through `--extern`, so the harness prints
//! the text one generated observation function returns. It holds no ordering
//! decision and re-implements no comparator. The case name is the first
//! program argument.

use cmpgen::comparison::ComparisonObserve;

fn observation(name: &str) -> Option<String> {
    match name {
        "int-ordinary" => Some(ComparisonObserve::comparison_observe_int_ordinary().to_utf8_lossy()),
        "int-extremes" => Some(ComparisonObserve::comparison_observe_int_extremes().to_utf8_lossy()),
        "array-order" => Some(ComparisonObserve::comparison_observe_array_order().to_utf8_lossy()),
        "nullable-order" => {
            Some(ComparisonObserve::comparison_observe_nullable_order().to_utf8_lossy())
        }
        "string-order" => Some(ComparisonObserve::comparison_observe_string_order().to_utf8_lossy()),
        _ => None,
    }
}

fn main() {
    let requested = std::env::args().nth(1);
    let requested = requested.unwrap_or_else(|| String::from("<none>"));
    match observation(requested.as_str()) {
        Some(text) => println!("{}", text),
        None => {
            eprintln!("comparison harness: unknown case {}", requested);
            std::process::exit(2);
        }
    }
}
