// Rust native harness. The runner copies this file into the generated
// crate at src/main.rs and builds with cargo --offline.
fn main() {
    use generated::trytail::try_tail_oracle::TryTailOracle;
    println!("p1-init={}", TryTailOracle::try_tail_oracle_p1_init());
    println!("p1-ret={}", TryTailOracle::try_tail_oracle_p1_ret());
    println!("p1-handler={}", TryTailOracle::try_tail_oracle_p1_handler());
    println!("p2-init={}", TryTailOracle::try_tail_oracle_p2_init());
    println!("p2-ret={}", TryTailOracle::try_tail_oracle_p2_ret());
    println!("p2-handler={}", TryTailOracle::try_tail_oracle_p2_handler());
    println!("p3-init={}", TryTailOracle::try_tail_oracle_p3_init());
    println!("p3-ret={}", TryTailOracle::try_tail_oracle_p3_ret());
    println!("p3-handler={}", TryTailOracle::try_tail_oracle_p3_handler());
    println!("p4-init={}", TryTailOracle::try_tail_oracle_p4_init());
    println!("p4-ret={}", TryTailOracle::try_tail_oracle_p4_ret());
    println!("p4-handler={}", TryTailOracle::try_tail_oracle_p4_handler());
}
