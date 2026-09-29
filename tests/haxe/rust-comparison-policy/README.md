# Rust comparison consumer check

Run from the repository root with `nix develop -c bash tests/haxe/rust-comparison-policy/run.sh`.
The authored expected values follow the sorted-key rules in
`docs/specs/stdlib/16-dataclass-sorted-keys.md`. The runner generates Haxe,
compiles a Rust library and native harness, then runs cases that distinguish
signed order, first differing sequence element, null order, UTF-16 order,
enum helper identity, and generic parameter order. Each attempt retains
commands, exit codes, raw streams, and SHA-256 hashes in
`out/rust-comparison-policy`.

The `generic-sequence` case compiles the generic record
`comparison.GenericRustKey.GenericSequenceKey<T>` for Rust. A generic
comparator binds each parameter the plan compares directly to a parameter
trait that supplies `u32` and `UString`; a parameter the plan does not
compare carries no bound. A nested generic reference adds the nested trait
bound beside the outer parameter bound. The shared fixture
`comparison.ParameterCompositionCases` covers the generic composition
cases: direct and unused bare type parameter fields, a nested record
element, a nullable element, and a sequence element. The generic data class
construction renders a zero-sized PhantomData marker for a parameter no
stored field references, clones the borrowed parameter in the constructor
initializer, and passes type parameter arguments by reference at the call
site.

The `unused-param-key` case accepts the unused parameter end-to-end: a
generic key whose parameter takes no stored field. The comparator takes no
trait bound for that parameter, the crate compiles, and the builder at a
record type reports the stored field order.

The generated comparison code is checked for zero new numeric casts. The
comparator reinterprets same-width integer storage into the signed i32 domain
by byte copy, never by an as cast, and the `no-as-cast` stage fails the run
when the emitted cast text appears in any generated comparison module. A
planted probe file carrying one cast line and one UFCS trait path line must
count exactly one match, which pins the detection and the exclusion of the
UFCS syntax (`no-as-cast-negative`).

Three negative controls bound the checks:

- `reject-float-key`: a stored Float field is outside the sorted-key domain.
  The source gate rejects the builder construction with the domain
  diagnostic, and a zero exit or a different diagnostic defeats the control.
- `reject-record-parameter`: a generic key whose parameter is bound to a
  record type. The source gates admit the shape, and generation exits zero;
  the parameter trait supplies `u32` and `UString` only, and the target
  compiler rejects the instantiation with the missing trait bound diagnostic
  E0277. A zero rustc exit or a different error defeats the control. A record
  actual at a parameter slot is a remaining target capability gap.
- `mutation`: the compiled harness runs one case against a deliberately
  wrong expectation line. The comparison step must report the mismatch, and
  a matching comparison defeats the control.
