# A3 consumer audit review

## Evidence and acceptance scope

Goose inspected the compiler at checkpoint `e5e21854`. The coordinator checked
that `packages/` is unchanged between that checkpoint and `ac6889dd`, then
checked the gates and callers below. This review records static source evidence.
It runs no generator or native compiler and establishes no regression result.
The original external report is retained as `goose-a3-consumer-audit-report.md`.
Its migration recommendations require the corrections recorded here.

## Verified consumers constrain the migration

Paths in this table are relative to `packages/compiler/`.

| Owner | Verified source location | Migration requirement |
| --- | --- | --- |
| Shared field classification | `ComparatorPlan.hx:13` | Replace outer and inner spelling-match flags with canonical source facts. Keep stored-field order and filtering. |
| TypeScript comparator | `reflaxe/ts/tscompiler/TsDecl.hx:182` | The helper prepass reads raw fields while the body consumes entries. Both must consume the selected comparison plan. |
| Kotlin comparator | `reflaxe/kotlin/kotlincompiler/KotlinDecl.hx:374` | Emission checks `:dataClass` without calling the capability wrapper. Adding a gate changes behavior and requires explicit evidence. |
| Kotlin nullable helper preparation | `reflaxe/kotlin/kotlincompiler/KotlinDecl.hx:395` | This is a live caller of `rawArrayElement`. Replace its decision together with the body and helper references. |
| Rust nullable classification | `reflaxe/rust/rustcompiler/RustDecl.hx:523` | This live caller and inline field classification must consume the shared source result and target comparison plan. |
| Swift nullable classification | `reflaxe/swift/swiftcompiler/SwiftDecl.hx:352` | Replace its `SwiftType.rawArrayElement` query together with inline field classification. |
| Swift equality | `reflaxe/swift/swiftcompiler/SwiftType.hx:342`, `reflaxe/swift/swiftcompiler/SwiftExpr.hx:2442` | Comparator capability influences the choice of equality operator. Keep its contract separate from sorted-key admission. |

`TsDecl.rawArrayElement` at line 278 and `DartDecl.rawArrayElement` at line 448
have no caller beyond self-recursion at this checkpoint. The external report
described all five target copies as consumed by nullable branches; that claim
is incorrect for these two. A deletion inventory must distinguish a live call,
a recursive reference inside an unused function, and an imported definition.
`KotlinType.canEmitDataClassComparator` also has no caller at this checkpoint.

## The coordinator rejects unsupported semantic conclusions

The audit correctly identifies Swift's equality consumer, then recommends
adapting Swift comparator capability to the shared sorted-key domain. Those
conclusions conflict. Swift currently supports scalar `Float` and `Bool`
comparison outside spec 16's key domain. The
[A3 design](a-comparator-migration.md) retains distinct source admission and
target planning decisions. A transitional capability predicate asks whether
the target plan succeeds; it does not maintain a separate optimistic traversal.

The audit's proposed same-name example returns from `A.Point` through `B.Point`
to `A.Point`. That path contains a real cycle. Use the acyclic counterexample
in the design to distinguish declaration identity from a short name. Retain
actual type arguments when comparing instantiated declarations.

The audit also claims that following a typedef guarantees admission of its
read-only-array form. `Context.follow` can erase the abstract to `Array`;
the result depends on the actual input handle and phase. The accepted A fixture
establishes its observed `PlainField` classification for an alias. It does not
establish that every target admits the source or reaches the reported body.
Generation and caller evidence remain required for those conclusions.

Foreign same-name declarations expose differences between predicates, but a
source rejection can prevent a cited body from running. Keep these as bounded
static hypotheses until source admission and the executed consumer are known.
A difference between two predicates alone does not establish a missing helper
in generated code. Package and name checks also differ from the canonical
module identity that A2 must establish.

## Guidance changes and the next evaluation

The audit brief already separated source admission, optional comparator
emission, and equality. Its contrary recommendation is a deviation from that
instruction. The later A3 design document was not in the original reading list.
Implementation briefs will name that document and include the Swift scalar
equality counterexample and the acyclic same-name case explicitly.

The coordinator retains the verified inventory without requesting another
report-format revision. The next implementation must demonstrate one selected
plan for helpers and body, deletion of the superseded live decisions, preserved
equality behavior, and independent source-admission results. A successful
generation subset cannot establish these broader migration requirements.
