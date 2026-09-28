# A: Enum comparison evidence

## Acceptance scope

The coordinator accepts the enum comparison fixture as reproducible evidence
of an unresolved source ruling. This delivery changes tests and documentation.
It establishes no new payload-enum semantics and repairs no comparator.

GLM authored the observation at `8a2a9c6a`. Luna adopted the shared stage
membership checker against `d873da91`; the coordinator copied the twelve
authored files and verified them in the integration checkout at `f3a8955a`.
The private checker was removed. Each attempt records the shared checker's
digest among its selected inputs.

## Observed behavior and rule scope

The source constructs record keys containing `Value(1)` and `Value(2)`.
TypeScript and Rust both return zero when comparing those records and false
from `RecordEq.eq`. Inserting both keys leaves one map slot with the second
value. The sorted table therefore follows its supplied comparator; the
disagreement originates in comparison and equality decisions.

Standard library specification 16 permits payload-enum fields and prescribes
constructor declaration order, while also requiring record comparison to
return zero exactly when generated equality returns true. These observations
expose a conflict between those requirements for the admitted source case.
The source ruling remains pending.

The direct payload-enum key rejection in specification 07 concerns another
domain. It does not by itself exclude an enum field inside a record key.
Feature 01's parameterless-enum amendment also cannot establish general
payload-enum equality. The two targets disagree for separately constructed
records holding the same payload: Rust returns true and TypeScript false.
The fixture records that difference without assigning an unsupported ruling.

## Integration evidence

The retained integration attempt is
the recorded run with suffix `HyHtFC`, verified at `f3a8955a`. Its ten expected stage
names exactly match the ten recorded stages. All five targets generated the
accepted record case. The direct payload-enum key probe exited one with the
expected rejection diagnostic. Rust library compilation, harness compilation
and execution exited zero; the TypeScript execution also exited zero.

The coordinator checked the actual files against all 33 selected input
digests and checked that before/after digests agree. These selected inputs
include 13 compiler files. The complete compiler closure remains unmeasured.
Each stage retains its argument bytes, working directory, separate streams and
status. The loaded boring path names the integration checkout.

Only TypeScript and Rust have native execution evidence here. Kotlin, Swift
and Dart have generation evidence. Rust emits four warnings: unused `DerefMut`,
unused `byte_to_unit`, and two elided-lifetime syntax warnings. This delivery
establishes no zero-warning or complete platform acceptance result.

The corrected original attempt (suffix `vqfMH4`), shared-checker adoption
attempt (suffix `IlGju9`), and integration attempt preserve the same
observations. Earlier scratch commands reused paths and truncated combined
streams; their missing historical states remain an evidence limitation.

## Guidance from review

An observation runner can complete successfully while retaining a semantic
disagreement. Its completion means its declared observations were obtained;
the source ruling determines compiler acceptance. A future semantic repair
must update the expectations from the resolved ruling and verify comparison,
equality, duplicate-key behavior and both operand orders together.

The report originally applied rules outside their stated domains. Review
corrected those claims before integration. Later tasks must identify the
actual semantic subject and the scope of the cited ruling before proposing a
shared policy. Existing implementation behavior alone cannot settle a conflict
in the source specification.
