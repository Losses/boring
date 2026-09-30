# xs-crossmod (reviewer-authored probe, archived verbatim)

Shape: TWO payload exception classes (`xsxm.CrossProbe.E1`, `.E2`) in ONE Haxe
module; their payload enums live in TWO DIFFERENT modules (`xsxm.Faults1.F1Fault`,
`xsxm.Faults2.F2Fault`). In this shape `payloadEnumNames` does not collide, but
`exceptionPayloads` (keyed by the exception CLASS's module) collides between E1
and E2 -> "whoever is scanned last wins".

## Driver (from a worktree containing this fixture under tests/haxe/)

    cd <worktree>
    HAXELIB_PATH=<worktree>/.haxelib \
    haxe tests/haxe/xs-crossmod/gen/rust.hxml -D rust-output=<genrel>/xs-crossmod
    cd <genrel>/xs-crossmod
    CARGO_TARGET_DIR=<fresh-dir> cargo build --offline

(see evidence/tools/run-matrix-mine.sh for the exact runner; it records gen rc
and cargo rc separately, uses a FRESH CARGO_TARGET_DIR per run, and logs a
`Compiling generated` count so a cargo cache replay cannot masquerade as a run)

## Expected readings (compiler state anchored by sha256 in evidence/raw/*.state.txt)

| compiler state | gen | cargo | error classes |
|---|---|---|---|
| frozen (pre earlier fix) | 0 | 101 | {E0277, E0433 x2, E0599 x2, E0609} |
| frozen + rust-payload-key-fix PATCH.diff ("earlier fix") | 0 | 101 | {E0609} (no field `fault` on type `F1Fault`) |
| earlier fix + this work's PATCH.diff | 0 | **0** | {} |
| earlier fix + reverse of this work's PATCH.diff | 0 | 101 | {E0609} again |

Key generated-Rust signature (pre, `xsxm/cross_probe.rs`): `rethrow_e1` keeps
raw `e.fault` while `rethrow_e2` is rewritten — the surviving "last scanned
wins" mirror. Post, both are rewritten:
`Err(F1Fault::E1Fault(Box::new(E1::new(e))))` under `Result<u32, F1Fault>`.

## Runner / CI status

NOT collected by any runner: no script, manifest or CI gate in the repository
references this fixture (checked in the audited worktree and this scratch
tree). It exists only in untracked worktree copies plus this archive. Any
green here is a manual measurement, not a regression guard.
