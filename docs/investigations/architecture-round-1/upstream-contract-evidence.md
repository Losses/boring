# Upstream fixes and responsibility contracts

## Revision and evidence scope

This review compares fixed baseline
`e3b8bab39ac2da0e17e9d04e031f03bd39290274` with remote master
`cc9957dd7f624f4deced5e722d2a57b45e0c2d36`, observed on 2026-09-28.
The architecture worktree remains based on the fixed baseline. This review
inspected source diffs without integrating changes or running their tests.

Merge `f0a31387` brings in a side history whose fixes have September 27
timestamps. Reachability after the baseline does not mean every fix was
written during this investigation. Commit counts alone cannot establish an
architectural defect.

## Observed decisions

| Revisions and source owner | Observed mechanism | Contract to investigate |
| --- | --- | --- |
| `1b4a2ad6`, `tscompiler/TsExpr.hx` | Destination array slots activate conversion of native data tables; indexed reads retain the native representation. Return, initializer, assignment, and argument paths carry this context. | Separate actual value representation from destination requirements. Identify formal parameter contracts when selecting argument conversions. |
| `02be3f51`, `PolicyQueries.hx`; `40657e31`, `007f9f19`, `rustcompiler/RustExpr.hx` | Shared typedef matching handles null-inflated anonymous types. Rust consults declared field types when selecting optional wrappers and handles constant values separately. | Preserve declaration identity and field storage independently of contextual expression typing. The selected operation must report its produced representation. |
| `8214566d`, `kotlincompiler/KotlinExpr.hx`; `8bbe9700`, `rustcompiler/RustExpr.hx` | Kotlin distinguishes source non-null proofs from native smart-cast eligibility. Rust distinguishes an optional value from an already extracted match payload. | Flow analysis owns the proof and invalidation. Target lowering owns the actual binding and read operation. |
| `40657e31`, `rustcompiler/RustExpr.hx` | Match arms reconcile bare and optional result shapes, including payload bindings. | Each reachable arm reports its result. A join selects a common representation while preserving control flow. |
| `e0aa16a5`, `f1609ccf`, `AssignTargetPlan.hx` | Assignment checks recognize conversion fragments in rendered paths and distinguish selected interior-mutability readers. | An assignment destination needs evidence that it still denotes the original writable location. A value conversion cannot establish this property. |
| `cc9957dd`, `rustcompiler/RustDecl.hx` | The shared-interface table gains the exact name of the new regression interface. Existing entries name two Tiqian interfaces. | Explain how object identity requirements select shared storage for arbitrary accepted interfaces. A registered example establishes coverage of that entry. |

These observations fit the existing dimensions of representation, flow,
evaluation, identity, and calls. Assignment paths also require an explicit
distinction between a produced value and a writable location. The inspected
string recognizer supplies a bounded check; the review has not established
its completeness or reproduced a lost write.

This sample covers TypeScript, Kotlin, Rust, and shared modules. Corresponding
Swift and Dart paths in these upstream changes remain uninspected. Their
status cannot be inferred from the absence of a listed repair. The separate
Swift pilot supplies direct evidence of a representation handoff failure.

## Consequences for task design

Organize work by the fact that must survive between responsibilities. For the
current array pilot, a producer reports the representation it emitted, a
declaration establishes stable binding storage, and a consumer supplies its
required representation. The conversion plan relates those facts. Adding a
strategy interface without correcting its inputs leaves the original error.

For name-based integration, identify the authority for each entry: a specified
standard library operation, a declared extern contract, or a semantic
requirement inferred from accepted source. When general source behavior is
required, a regression must exercise an ordinary previously unregistered type.
Registering a test-specific name in the implementation can verify that entry;
it cannot establish the general selection rule.

Record the rule's producer and consumer coverage before implementation.
Use interaction tests where the next consumer depends on the intermediate
representation. In the Swift pilot, indexing a mistakenly mutable result
passed; passing it to a required read-only parameter exposed the mismatch.
Choose additional forms from the contract's dependencies, including identity,
evaluation, and flow, and retain the original failure.

The next implementation remains the
[prepared array value contract](j-representation-contract.md). Interface
identity policy and assignment-place representation remain separate scheduled
mechanisms. Their evidence informs the common analysis method without adding
unreviewed compiler changes to the current candidate.
