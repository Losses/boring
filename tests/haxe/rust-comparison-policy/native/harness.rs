use cmpgen::comparison::ComparisonObserve;
use cmpgen::comparison::GenericRustKey;
use cmpgen::comparison::ParameterCompositionCases;

fn main() {
    let name = std::env::args().nth(1).unwrap_or_default();
    let value = match name.as_str() {
        "int-extremes" => ComparisonObserve::comparison_observe_int_extremes(),
        "array-order" => ComparisonObserve::comparison_observe_array_order(),
        "nullable-order" => ComparisonObserve::comparison_observe_nullable_order(),
        "string-order" => ComparisonObserve::comparison_observe_string_order(),
        "nullable-int-order" => ComparisonObserve::comparison_observe_nullable_int_order(),
        "mixed-sign-array-order" => ComparisonObserve::comparison_observe_mixed_sign_array_order(),
        "shared-enum-helpers" => ComparisonObserve::comparison_observe_shared_enum_helpers(),
        "generic-sequence" => GenericRustKey::generic_rust_key_observe(),
        "parameter-composition" => ParameterCompositionCases::parameter_composition_cases_observe(),
        _ => {
            eprintln!("unknown case: {name}");
            std::process::exit(2);
        }
    };
    println!("{}", value.to_utf8_lossy());
}
