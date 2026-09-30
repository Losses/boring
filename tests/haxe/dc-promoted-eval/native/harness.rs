//! Native invocation driver for the dc-promoted-eval fixture (Rust).
//!
//! Unlike the other targets the Rust emitter publishes the probe counter as a
//! `pub static ...: Mutex<u32>` and the probes as associated functions of a
//! zero-sized struct, so the driver is a separate crate and reaches them
//! through `--extern pe=<the generated lib>`. The driver only observes: it
//! resets the probe counter, calls the probe once, and prints the counter. It
//! takes no verdict; the runner compares the printed observation with the
//! authored expectation.

use pe::dcpe::double_eval_control::{DoubleEvalControl, DOUBLE_EVAL_CONTROL_CALL_COUNT};
use pe::dcpe::eval_probe::{EvalProbe, EVAL_PROBE_CALL_COUNT};

use std::sync::Mutex;

fn counter(cell: &Mutex<u32>) -> u32 {
    *cell.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn main() {
    let requested = std::env::args().nth(1).unwrap_or_else(|| "<none>".to_string());
    match requested.as_str() {
        "promoted" => {
            EvalProbe::eval_probe_reset();
            let acc = EvalProbe::eval_probe_promoted_once();
            println!(
                "case=promoted acc={} callCount={}",
                acc,
                counter(&EVAL_PROBE_CALL_COUNT)
            );
        }
        "double" => {
            DoubleEvalControl::double_eval_control_reset();
            let acc = DoubleEvalControl::double_eval_control_double_once();
            println!(
                "case=double acc={} callCount={}",
                acc,
                counter(&DOUBLE_EVAL_CONTROL_CALL_COUNT)
            );
        }
        other => {
            eprintln!("dc-promoted-eval rust driver: unknown case {}", other);
            std::process::exit(2);
        }
    }
}
