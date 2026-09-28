//! Native harness for the generated enum comparison crate.
//!
//! The harness calls the generated public entry points and prints one line
//! per read. It constructs no record, builds no table, and holds no
//! expectation about the generated behavior; the expected values live in
//! the runner.

use enumgen::enumcomparison::enum_comparison_subject::compare_tag_key;
use enumgen::enumcomparison::enum_comparison_subject::EnumComparisonSubject;
use enumgen::runtime::u_string::UString;

fn text(value: UString) -> String {
    value.to_utf8_lossy()
}

fn main() {
    println!("[native] start");
    println!(
        "mapDistinctPayload={}",
        text(EnumComparisonSubject::enum_comparison_subject_map_distinct_payload())
    );
    println!(
        "mapSamePayload={}",
        text(EnumComparisonSubject::enum_comparison_subject_map_same_payload())
    );
    println!(
        "mapDistinctTags={}",
        text(EnumComparisonSubject::enum_comparison_subject_map_distinct_tags())
    );
    println!(
        "eqDistinctPayload={}",
        EnumComparisonSubject::enum_comparison_subject_eq_distinct_payload()
    );
    println!(
        "eqSamePayload={}",
        EnumComparisonSubject::enum_comparison_subject_eq_same_payload()
    );
    println!(
        "eqDistinctTags={}",
        EnumComparisonSubject::enum_comparison_subject_eq_distinct_tags()
    );
    let value1 = EnumComparisonSubject::enum_comparison_subject_key_value1();
    let value1_again = EnumComparisonSubject::enum_comparison_subject_key_value1_again();
    let value2 = EnumComparisonSubject::enum_comparison_subject_key_value2();
    let blank = EnumComparisonSubject::enum_comparison_subject_key_blank();
    println!("compareKeyValue1KeyValue1Again={}", compare_tag_key(&value1, &value1_again));
    println!("compareKeyValue1KeyValue2={}", compare_tag_key(&value1, &value2));
    println!("compareKeyValue1KeyBlank={}", compare_tag_key(&value1, &blank));
    println!("[native] end");
}
