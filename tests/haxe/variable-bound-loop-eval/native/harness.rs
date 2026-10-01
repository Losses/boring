//! Native invocation driver for the variable-bound-loop-eval fixture (Rust).
//!
//! The Rust emitter publishes the probe as a zero-sized struct with
//! associated functions in module `vble::probe` of the generated crate, so
//! the driver is a separate crate and reaches them through
//! `--extern vble=<the generated lib>`. The driver only observes: it calls
//! the three generated probe functions once each and prints the three
//! returned bound-read counts. The generated `probe_main` calls the fixture
//! shadow of haxe.Log (a no-op), so this driver is the only printer of the
//! observation line. It takes no verdict; the runner compares the printed
//! observation with the authored expectation.

use vble::vble::probe::Probe;

fn main() {
    let local = Probe::probe_local_bound();
    let length = Probe::probe_growing_length();
    let control = Probe::probe_double_control();
    println!("local={} length={} control={}", local, length, control);
}
