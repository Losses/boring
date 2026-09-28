# A and E: Integer comparison operation boundary

## Reviewed specification

The GLM review at `8a2a9c6a` separates source ordering from target storage.
Feature 07 gives Haxe Int its signed 32-bit domain. Standard library
specifications 07 and 16 require numeric Int key ordering. Feature 14 maps
business Int storage to Rust `u32` and resident storage to `i32`, with explicit
boundary adaptation. The source key gate admits Int without a sign predicate.
Its acceptance therefore cannot be explained by assuming all keys are positive.

Feature 52 records the negative-value limitation of the Rust mapping as an
independent issue. It supplies no new source restriction. The coordinator
accepts the distinction between these rule domains and the requirement for a
representation-aware source-order operation. This review selects no global
change to Rust storage.

## Actual consumers

The coordinator inspected the integration source at `cde5e97c`. Rust's direct
Int key path in `RustExpr.sortedComparator` adapts each operand with
`RustConversions.reinterpret` and calls the signed resident comparator.
Record-field comparison has separate unsigned operations. The earlier fixture
observes the resulting wrong order at signed limits. The operation's source
semantics agree across these consumers; their actual operand representations
determine the required adaptation.

Swift's direct Int key path selects `SortedTable.compareInts` and registers
its runtime dependency. Record-field comparison separately emits subtraction,
which the fixture observes trapping at signed limits. Unequal Int sequence
elements also use an independent branch that can return positive results for
both operand orders. The assigned Swift plan must compose the same safe child
operation through scalar, nullable and sequence shapes.

Kotlin's nullable scalar `TAbstract` field branch calls `toString().compareTo`.
The coordinator verified that source branch statically. Decimal string order
does not implement integer order for such pairs as 2 and 10. The existing
runtime fixture has no nullable scalar Int case, so this remains a static
finding with a required discriminating case for the Kotlin migration.

## Rejected dependency assumption

The GLM proposal reuses `RustConversions.reinterpret`, while acknowledging an
`as` expression inside it. The helper's header claims zero numeric casts; its
current body renders a cast before the byte conversion. The repository's
zero-`as` rule still applies. The coordinator rejects treating an existing
helper as an automatic exception to that rule.

The later Rust task must establish the source and destination integer widths
at selection time and use a legal typed realization. It must distinguish
bit-pattern decoding of the source Int representation from a checked numeric
conversion. Reinterpreting the stored bits recovers the source signed value;
it does not preserve unsigned numeric order. Validation must include both
operand orders, signed limits, mixed signs, nullable scalar values and sequence
elements. Helper selection also carries its declaration/import dependencies.

The proposed source-order operation is accepted as an architectural input.
The particular Rust helper reuse is unaccepted pending that implementation
review. The current task changes no Rust compiler code.

## Evidence scope and next work

The frozen comparison attempt is `comparison-dDuBYCYk` in the original
observation checkout. Its 25 runtime case observations contain 21 matching
outcomes and four nonmatching outcomes. Kotlin's whole-tree compile failure is
separate; its five runtime observations use the recorded reduced input that
excludes the test runtime. The earlier report's count combined these categories.

The independent review is `claude-integer-comparison-report.md`. Its source
inventory informs the upcoming target adapters; it does not establish fresh
runtime results. The Swift writer has received the additional nullable scalar
and mixed-sign sequence cases. Other target migrations and the full Boring and
Tiqian gates remain required.
