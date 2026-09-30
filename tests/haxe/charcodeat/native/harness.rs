// Rust native harness. The runner copies this file into the generated
// crate at src/main.rs and builds the crate with cargo --offline.
//
// Signature notes (matched against the generated lowering at
// pinned e1c65975): the Nullable-context shapes
// (char_code_at_oracle_code_null / _code_neg) return Option<u32>;
// the Int-context shape (char_code_at_oracle_code_int) returns a bare
// u32, so it is rendered without Option normalization -- a miss is
// whatever the generated lowering puts there, and that raw value is
// the observation. Option misses render as the token "null".
fn text(v: Option<u32>) -> String {
    match v {
        Some(x) => x.to_string(),
        None => "null".to_string(),
    }
}

fn main() {
    println!(
        "subRev={}",
        generated::charcodeat::char_code_at_oracle::CharCodeAtOracle::char_code_at_oracle_sub_rev()
    );
    println!(
        "subHigh={}",
        generated::charcodeat::char_code_at_oracle::CharCodeAtOracle::char_code_at_oracle_sub_high()
    );
    println!(
        "subNeg={}",
        generated::charcodeat::char_code_at_oracle::CharCodeAtOracle::char_code_at_oracle_sub_neg()
    );
    println!(
        "codeNull={}",
        text(generated::charcodeat::char_code_at_oracle::CharCodeAtOracle::char_code_at_oracle_code_null())
    );
    println!(
        "codeNeg={}",
        text(generated::charcodeat::char_code_at_oracle::CharCodeAtOracle::char_code_at_oracle_code_neg())
    );
    println!(
        "codeInt={}",
        generated::charcodeat::char_code_at_oracle::CharCodeAtOracle::char_code_at_oracle_code_int().to_string()
    );
}
