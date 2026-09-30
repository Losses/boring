// Rust native harness for the try-tail-min fixture.
fn main() {
    use generated::trytailmin::min_oracle::MinOracle;
    println!("rethrow-handler={}", MinOracle::min_oracle_rethrow_handler());
    println!("plain-throw={}", MinOracle::min_oracle_plain_throw());
}
