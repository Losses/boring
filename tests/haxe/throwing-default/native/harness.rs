// Rust native harness. The runner copies this file into the generated
// crate at src/main.rs and builds with cargo --offline.
//
// Signature notes (matched against the generated lowering at base
// e8648488): the three probe functions return the plain UString (the
// try region lowered itself to a Result match, leaving the probe
// signatures unwrapped), so the harness calls them directly. The raw
// callers (call_omitted_safe / call_omitted_throwing / call_explicit)
// are Result<u32, ThrowingDefaultFault> and resolve is
// Result<u32, ThrowingDefaultFault> with the coalescing default
// lowered inside unwrap_or_else as
// throwing_fallback(seed).unwrap() -- a panic on the throwing
// omission shape. The harness therefore prints the safe lines first
// and the throwing line last: a panic there truncates the output and
// the process exit is the observation.
fn main() {
    use generated::throwdef::ThrowingDefaultOps;
    println!(
        "omittedSafe={}",
        ThrowingDefaultOps::throwing_default_ops_probe_omitted_safe()
    );
    println!(
        "omittedThrowing={}",
        ThrowingDefaultOps::throwing_default_ops_probe_omitted_throwing()
    );
    println!(
        "explicit={}",
        ThrowingDefaultOps::throwing_default_ops_probe_explicit()
    );
}
