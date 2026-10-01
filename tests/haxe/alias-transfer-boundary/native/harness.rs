// Rust native harness. The runner copies this file into the generated
// crate at src/main.rs and builds the crate with cargo --offline.
fn main() {
    println!("field={}", generated::atb::container_alias_oracle::ContainerAliasOracle::container_alias_oracle_field());
    println!("fieldNull={}", generated::atb::container_alias_oracle::ContainerAliasOracle::container_alias_oracle_field_null());
    println!("fieldRebind={}", generated::atb::container_alias_oracle::ContainerAliasOracle::container_alias_oracle_field_rebind());
    println!("relay={}", generated::atb::container_alias_oracle::ContainerAliasOracle::container_alias_oracle_relay());
    println!("relayFresh={}", generated::atb::container_alias_oracle::ContainerAliasOracle::container_alias_oracle_relay_fresh());
}
