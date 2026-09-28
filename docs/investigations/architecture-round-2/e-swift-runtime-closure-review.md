# E: Swift ordinary runtime dependency closure

## Scope and decision

The coordinator accepts this bounded declaration-ownership and dependency
registration correction after reviewing the exact source and running the
focused fixture in the integration checkout. The executor's input was
`0dd54d25eccbedf810f2e44fe53294dbbb7031ad`. Its historical worktree/task name
contains `D1`; that assignment label was incorrect. Runtime module closure
belongs to package E, with package A's representation dependency. Package D's
control-flow result migration remains separate work.

The four compiler files are `SwiftRuntime.hx`, `Compiler.hx`, `SwiftType.hx`,
and `SwiftExpr.hx`. The ordinary runtime now owns the existing `TiqianArray`
and `ReadOnlyArray` declarations in `ARRAY_SOURCE`; the test host owns only its
test support. The coordinator compared the moved array fragment with the base
and found its bytes unchanged. Ordinary and test emission no longer compete
for ownership of these declarations.

Both Array type-mapping entries register the selected runtime dependency.
Expression materialization uses `arrayRuntimeText`, which records that same
dependency and returns its input text unchanged. This is a transitional use
of the existing import/dependency protocol. It does not classify rendered
text, select a conversion, or establish a flow fact. Runtime emission and
resident-module handling still use the existing compiler configuration and
selection rules; this delivery does not replace the full module-closure model.

## Why the type-only change was insufficient

The first candidate registered Array type mappings. The coordinator then
identified direct materialization paths that ask for the element type only.
The executor reproduced `return [3, 7][index]` with an Int result and no
Array-typed variable or signature. It emitted `TiqianArray<Int32>([3, 7])`
without `Runtime.swift`; Swift compilation failed at that reference.

The corrected dependency registration covers the actual constructor paths,
including literals and `new Array`, empty defaults, fill allocation, selected
array boundary output, process arguments, string split, mutable-array slice,
and filesystem array results. The native Swift Array slice branch retains its
existing behavior. Some of these paths are inspected statically; the fixture
executes the literal, constructor and sharing paths listed below.

The lesson for later policy work is to account for both declarations and
produced values. A type-mapping visit cannot prove that every emitted operation
registered its required declaration. A dependency belongs to the selected
representation or operation, including operations whose enclosing result has
a different source type.

## Integration evidence

The external handover is `luna-d1-runtime-closure-report.md`. The coordinator
retains exact copied file hashes in `swift-closure-integrated-files.json` and
source inspection in `root-swift-closure-source-review.json`.

The coordinator's retained command is
`out/swift-runtime-closure-root-qa/review-duk6zwvr/command.json`; its separate
stdout, stderr, numeric status and 131 before/after compiler/fixture hashes
are beside it. The hashes agree. The command recorded the integration checkout
as the loaded boring library and Swift 6.2.4 on Linux. It invoked the existing
fixture runner and exited zero. The generated attempt is
`out/swift-runtime-closure/attempt-G97AfDsU`.

| Authored operation | Native result |
| --- | --- |
| Mutable Array converted to a read-only view, then owner mutation | `5`, including the later element seen through the view |
| Array constructor, push, copy, index and length without test discovery | `4` |
| Immediate array literal/index with scalar result | `7` |
| Normal test discovery and test-host compilation | JSONL test verdict `pass` |

Each of the four generated runtime files contains one declaration of each
array type. The generated test host contains neither declaration. Ordinary
cases emit no test host. The captured integration stderr contains the Nix
dirty-checkout notice and no native compiler warnings.

The executor retains the base missing-declaration diagnostic and the earlier
scalar-expression failure. Earlier fixed-output experiments were overwritten;
their final tree was preserved before switching to unique attempt directories.
Those missing earlier states cannot be reconstructed. Review also found that
the new runner assumed its output parent already existed. The executor added
parent creation and verified a previously absent nested parent. The integration
run then exercised the default parent in the receiving checkout.

The pinned formatter requires a few existing expressions to be wrapped
differently. The executor demonstrated that removing those formatting-only
hunks fails the formatter check. They carry no intended semantic change.

## Remaining acceptance boundaries

An independent Goose source review is running against a 122-file hash-checked
snapshot matching the compiler handover. Its findings will supplement this
coordinator review. It is not yet a completed independent acceptance result.

The unfinished Swift prepared-value and boundary work remains open, as do the
newly observed comparator defects. Existing branded mutable-array and exception
names remain separate recorded migration work. This correction establishes no
full Swift platform, Boring matrix, or fixed-version Tiqian regression pass.
