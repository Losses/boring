# T2 consumer preparation review

## Accepted static inputs

The coordinator accepts the reconstructed configuration inputs in the locked
`architecture-workspaces/tiqian-validation-round2` checkout at
`8504d230228e8206689a2049bbb84b671c1f079a`. This accepts static preparation only.
Generation, native execution, test-ID agreement and regression remain unverified.

The preparation recorded coordinator revision `8a5aa83a`, actual working-file
hashes and its documentation-only delta from the task's earlier revision.
Later coordinator changes require new candidate identity evidence before tests.

### Later coordinator checkpoint

The coordinator reached `039e1a43` after the terminology and candidate-review
commits. Its path difference from `8a5aa83a` includes compiler and fixture
files, so the preparation tool's documentation-only revision allowance does
not apply. The existing twelve derived HXML files and three project files
remain evidence for the earlier static preparation. They do not identify
the current Boring candidate's complete inputs.

After A, B, and F candidates are accepted, select one Boring revision. Keep
its inputs unchanged while rerunning static preparation against that exact
revision. Independently check the twelve generation and eleven target-test
obligations, the three protocol
test-root unions, the transformed HXML paths, and working-file hashes before
launching Tiqian generation. Keep the earlier attempt as historical evidence.

| Input or obligation | Verified result |
| --- | --- |
| Three derived root configurations | Complete project, engine comparison group and protocol comparison group retained |
| Generation and test membership | Twelve generation targets and eleven test targets; engine has eight tests and protocol has three |
| Comparison baselines | Engine uses `kotlin-f32`; protocol uses `protocol-ts` |
| Protocol coverage | All three tested targets retain the common eight test roots; missing roots were appended without deleting original roots |
| Protocol C | Generation retained, `test:false` retained, original `c-header.js` after-generation command retained |
| HXML transformation | Twelve expanded files and their differences retain source order, replace explicit package paths and add verbose compiler output |
| Other configuration properties | Source sets, source roots, recipes, output/result directories, bundle identifiers and metadata retained |

Preparation evidence is under
`out/architecture-t2/attempt-01-20260928T093930Z-1613971` in the consumer checkout.
The coordinator verified all 28 canonical output hashes against the manifest,
and verified each retained attempt copy independently. After the Nix environment
setup, all 2,635 tracked regular-file hashes and both tracked symbolic-link
targets still matched the pre-preparation inventory. The coordinator read the
derived group membership and the protocol-root transformation differences.

The 248 copied data files match the earlier setup inventory. One extra symbolic
link under the golden-data directory names an old external checkout; the inventory
records its target string without following it. The data's producing engine
revision remains unknown. These retained inputs still require a fresh regression
run against the fixed candidate.

## Environment evidence and execution requirements

The one environment identity attempt is retained under
`out/architecture-t2/identity-check-01`. Required identity commands returned zero
and have individual arguments, output streams and numeric statuses. The pinned
driver belongs to Boring revision `304ed70c`; its wrapper hash is
`af6aeef816ea615239e1d2cf17471aa3969d965a36993491e8446b166970289d`.
The shell hook's class-root output is unchanged.

The initial environment has no `swiftc` command on PATH. The attempted
`boring --version` and `kotlin --version` options also failed. Their actual errors
remain recorded separately from successful identity checks. The consumer flake
explicitly expects an external Swift wrapper; its absence does not establish
that Swift validation is impossible. Establish and record that toolchain before
the two Swift test obligations run. The coordinator Boring flake defines Swift
wrappers that can inform this preparation without modifying consumer source.

The consumer shell hook resets the Boring Haxelib mapping to its pinned export.
Set the candidate mapping after that hook and run generation in the same shell.
Opening another `nix develop` between those actions can restore the pinned
mapping. The external report's separate-shell example commands are unverified
and must not be used as a complete execution recipe. Inspect actual loaded
compiler paths in verbose generation output, including every explicit HXML path.

Before the final matrix, fix the Boring candidate, identify the driver actually
executed and verify its configuration compatibility. Execute engine and protocol
comparison groups sequentially with all their original obligations. Preserve
native warnings and failed stages; resolve missing test IDs through source
coverage, with no filtering of absent observations.

## Review corrections

The first preparation draft used Git index blob identities as working-file
evidence and did not retain independent copies of every attempt's outputs.
The revised tool hashes actual inputs and retains produced copies in the
exclusive attempt directory. Its expected target lists now come from the task
requirements and are checked against both source and derived configuration.

The first proposed identity script suppressed command failures and ended with
success. The coordinator stopped it before execution; the revised script retains
individual outcomes. These are instances of requirements already supplied in
the brief. Shared verification tooling should make their correct implementation
reusable across future tasks; repeating the written requirements has not prevented
these omissions.
