//! Native harness for the generated enum comparison contract crate.
//!
//! The harness calls the generated public entry points and prints one line
//! per read. It constructs no record, builds no table, and holds no
//! expectation about the generated behavior; the expected values live in
//! the runner.

use enumgen::enumcontract::enum_contract_subject::compare_tag_key;
use enumgen::enumcontract::enum_contract_subject::EnumContractSubject;
use enumgen::runtime::u_string::UString;

fn text(value: UString) -> String {
    value.to_utf8_lossy()
}

fn main() {
    println!("[native] start");
    println!(
        "mapDistinctPayload={}",
        text(EnumContractSubject::enum_contract_subject_map_distinct_payload())
    );
    println!(
        "mapSamePayload={}",
        text(EnumContractSubject::enum_contract_subject_map_same_payload())
    );
    println!(
        "mapDistinctTags={}",
        text(EnumContractSubject::enum_contract_subject_map_distinct_tags())
    );
    println!(
        "eqDistinctPayload={}",
        EnumContractSubject::enum_contract_subject_eq_distinct_payload()
    );
    println!(
        "eqSamePayload={}",
        EnumContractSubject::enum_contract_subject_eq_same_payload()
    );
    println!(
        "eqDistinctTags={}",
        EnumContractSubject::enum_contract_subject_eq_distinct_tags()
    );
    let value1 = EnumContractSubject::enum_contract_subject_key_value1();
    let value1_again = EnumContractSubject::enum_contract_subject_key_value1_again();
    let value2 = EnumContractSubject::enum_contract_subject_key_value2();
    let blank = EnumContractSubject::enum_contract_subject_key_blank();
    println!("compareKeyValue1KeyValue1Again={}", compare_tag_key(&value1, &value1_again));
    println!("compareKeyValue1KeyValue2={}", compare_tag_key(&value1, &value2));
    println!("compareKeyValue1KeyBlank={}", compare_tag_key(&value1, &blank));
    println!("[native] end");
}
