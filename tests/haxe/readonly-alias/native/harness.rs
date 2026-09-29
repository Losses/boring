// Rust native harness. The runner copies this file into the generated
// crate at src/main.rs and builds the crate with cargo --offline.
fn main() {
    println!("alias={}", generated::roalias::read_only_alias_oracle::ReadOnlyAliasOracle::read_only_alias_oracle_alias());
    println!("passed={}", generated::roalias::read_only_alias_oracle::ReadOnlyAliasOracle::read_only_alias_oracle_passed());
    println!("escaped={}", generated::roalias::read_only_alias_oracle::ReadOnlyAliasOracle::read_only_alias_oracle_escaped());
    println!("rebind={}", generated::roalias::read_only_alias_oracle::ReadOnlyAliasOracle::read_only_alias_oracle_rebind());
    println!("boundary={}", generated::roalias::read_only_alias_oracle::ReadOnlyAliasOracle::read_only_alias_oracle_boundary());
}
