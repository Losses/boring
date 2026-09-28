# F2: Shared stage membership delivery

## Responsibility and accepted change

The executor used checkout `policy-f-stage-membership` at
`f104e3bf1f76b53e3ca9378d4a70c14dad1598af`. The coordinator reviewed its exact
files before copying them into the integration checkout. This change gives
`tests/support/stage-check.sh` ownership of the existing stage membership
algorithm used by the place and source-container fixtures. Both private copies
are removed. The place fixture's focused checker also calls the shared file.

The function takes the status table, expected stage list, and findings path.
It reports missing, repeated, and unexpected stage identities. Its body is
byte-identical to the previous implementation. It does not establish that the
expected list was declared independently, that a producer succeeded, or that
the observed program implements the specified semantics. Those responsibilities
remain with the fixture and its evidence owner.

Both consumers include the shared file in their existing provenance records.
The source-container fixture also includes it in its before/after input
manifest. This preserves input identity when a dependency moves outside a
fixture directory. No new capture mechanism is introduced by this change.

## Checked evidence

The external handover is `goose-f2-membership-report.md`. The coordinator's
mechanical inspection is retained as `root-f2-worker-review.json`; exact copied
file hashes and removals are in `f2-integrated-files.json`.

| Check | Observed result |
| --- | --- |
| Shell syntax for the shared file and three callers | Four zero statuses |
| Existing membership test through the shared file | Zero status; detects a duplicate, a missing stage, and a prefix that is not the requested identity |
| Place fixture, `out/place-contract/runs/place-IV5QGh` | 48 unique recorded stages equal the expected set; existing native failures retain explicit dependent stages that were not reached |
| Source-container fixture, `out/source-container-policy/gen-ThvI7V` | 87 unique recorded stages equal the expected set; all 27 source-fact rows pass |
| Source-container input identity | 143 before/after entries agree and match the files read by the coordinator; the shared checker is included |
| Changed-file documentation and comment style | Zero hits |

The source-container native observations remain unchanged: TypeScript, Kotlin,
and Rust produce the expected output on both sides; Swift and Dart compilation
failures prevent their runtime checks. Rust warnings remain in the native
compiler streams. The fixture runner's zero status records a completed
observation procedure; it does not turn those native failures into passing
language tests. The full Boring and fixed-revision Tiqian requirements remain.

The handover report gives incorrect example paths for identity streams. The
place fixture records the shared hash in its attempt's `identity.txt`; the
source-container attempt records it in its existing identity step and input
manifests. The coordinator checked those actual files. The report's illustrative
paths are not evidence locations.

## Review and remaining work

The first edit copied one relative path to scripts at different directory
depths. Review required resolving each path from its own script directory;
the final three paths reach the same shared file. A proposed verification
pipeline would have reported the status of `tail`; it was cancelled before
execution, and both runners executed directly instead. These corrections apply
the analysis method's existing path and process-outcome requirements.

The coordinator limited consolidation to the equivalent membership algorithm.
Earlier proposals to combine different identity and child-capture contracts
were not accepted. Other active observation fixtures retain their separate
implementations until their owners adopt this reviewed shared dependency.
Child capture, expected-stage declaration, input retention, and semantic
evaluation still need their own explicit consumers and removal decisions.
