// Measurement body copied into the generated crate by measure-units-cost.sh.
// Kept beside the fixture so the reading is reproducible from the repository,
// not only from a scratch directory.
use generated::pch::per_char_units_probe::PerCharUnitsProbe;
use generated::runtime::u_string::{self, UString};
use std::time::Instant;

/// A numeric trace dump: mostly digits with a decimal point every few units --
/// the shape TestTraceRender.stripWholeFraction walks.
fn trace_text(bytes: usize) -> String {
    let unit = "1.2500,3.7500,0.1250,12.5000,";
    let mut s = String::with_capacity(bytes + unit.len());
    while s.len() < bytes {
        s.push_str(unit);
    }
    s
}

fn measure_strip(bytes: usize) -> (u64, u64, u128) {
    let text = trace_text(bytes);
    let owned = UString::from(text.as_str());
    let before = u_string::units_calls();
    let scanned_before = u_string::unit_at_scanned();
    let start = Instant::now();
    let out = PerCharUnitsProbe::per_char_units_probe_strip_whole_fraction(owned.as_ustr());
    let elapsed = start.elapsed();
    let _ = out.as_ustr().as_slice().len();
    (
        u_string::units_calls() - before,
        u_string::unit_at_scanned() - scanned_before,
        elapsed.as_millis(),
    )
}

fn measure_range_local(bytes: usize) -> (u64, u64, u128) {
    let text = trace_text(bytes);
    let owned = UString::from(text.as_str());
    let before = u_string::units_calls();
    let scanned_before = u_string::unit_at_scanned();
    let start = Instant::now();
    let total = PerCharUnitsProbe::per_char_units_probe_for_range_local_dot_count(owned.as_ustr());
    let elapsed = start.elapsed();
    assert!(total > 0);
    (
        u_string::units_calls() - before,
        u_string::unit_at_scanned() - scanned_before,
        elapsed.as_millis(),
    )
}

#[test]
fn perchar_units_cost() {
    for bytes in [100_000usize, 200_000, 400_000] {
        let (calls, scanned, ms) = measure_strip(bytes);
        println!(
            "MEASURE strip_whole_fraction bytes={} units_calls={} unit_at_scanned={} elapsed_ms={}",
            bytes, calls, scanned, ms
        );
    }
    for bytes in [100_000usize, 200_000, 400_000] {
        let (calls, scanned, ms) = measure_range_local(bytes);
        println!(
            "MEASURE for_range_local bytes={} units_calls={} unit_at_scanned={} elapsed_ms={}",
            bytes, calls, scanned, ms
        );
    }
}
