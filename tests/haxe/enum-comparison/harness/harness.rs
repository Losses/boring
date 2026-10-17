//! Native harness for the generated enum comparison crate.
//!
//! The harness calls the generated public entry points and prints one line
//! per read. It constructs no record, builds no table, and holds no
//! expectation about the generated behavior; the expected values live in
//! the runner.

use enumgen::enumcomparison::enum_comparison_subject::compare_rank_key;
use enumgen::enumcomparison::enum_comparison_subject::EnumComparisonSubject;
use enumgen::runtime::u_string::UString;

fn text(value: UString) -> String {
    value.to_utf8_lossy()
}

fn main() {
    println!("[native] start");
    println!(
        "mapDistinctTags={}",
        text(EnumComparisonSubject::enum_comparison_subject_map_distinct_tags())
    );
    println!(
        "eqDistinctTags={}",
        EnumComparisonSubject::enum_comparison_subject_eq_distinct_tags()
    );
    let first = EnumComparisonSubject::enum_comparison_subject_key_first();
    let first_again = EnumComparisonSubject::enum_comparison_subject_key_first_again();
    let second = EnumComparisonSubject::enum_comparison_subject_key_second();
    println!("compareKeyFirstKeyFirstAgain={}", compare_rank_key(&first, &first_again));
    println!("compareKeyFirstKeySecond={}", compare_rank_key(&first, &second));
    println!("[native] end");
}

