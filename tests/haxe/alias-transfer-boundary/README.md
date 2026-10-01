# REPORT — alias-transfer-boundary (container alias across nullable field and call boundary)

Task: `t-mum17vl5-9rty` (branch `audit/container-alias-nullable`).
This report distinguishes **what I measured myself** (the run I ran in this round `out/alias-transfer-boundary/runs/atb-Wn4rY37a`) from **what I cite** (the previous run `out/alias-transfer-boundary/runs/atb-whb18ccE`, used only for cross-checking; this round's own measurements match its per-stage readings).

## 1. The two input groups and the fixed Haxe oracle

The fixture has 15 items total, in two authored shapes (`atb/ContainerAliasOracle.hx`):

- **Shape (a) nullable-field unwrap**: `NullableHolder.values : Null<Array<Int>>`; the field is read back, unwrapped into a read-only view, and the retained mutable alias mutates the original container after the view is established. Three readings: `field` (shared read = 702, de-shared copy = 101), `fieldNull` (null control = 0), `fieldRebind` (field rebound to a new container after the view is established; retains original storage = 123, view follows the binding = 987).
- **Shape (b) call relay**: `relayThrough(Array→ReadOnlyArray parameter, returns ReadOnlyArray)`; the caller retains a mutable alias and mutates after the call. Two readings: `relay` (argument/return shared = 3301, copy at either position = 1201), `relayFresh` (fresh control = 0).

The authored expected row (`expected.txt`, fixed): `field=702 / fieldNull=0 / fieldRebind=123 / relay=3301 / relayFresh=0`.

Source hashes (sha256, measured by me; this round matches the identity stage `identity/authored-source-hashes` record):

```
64fde642d4b4e5a7182720f42ad7498f7bb8f232ee1c014f86fe4406d704c200  atb/ContainerAliasOracle.hx
c008bc24f1e0c7ebdcd35fcdc2f39cde19abed11618ead0c9f65e585ad61f9eb  atb/NullableHolder.hx
e7369e7fd99f6b22c495d6be6fc2d5023c4ad9d2184ea55abe765960e9a93d3c  expected.txt
9f451c44e6e8931f7c48b78df47431e3f79ef978f4722701137f4ff908b52c7e  run.sh
```

The before/after input manifests (`input-hashes-before.txt` / `input-hashes-after.txt`) are byte-for-byte identical (`input-hashes-after observed=0`); the fixture was not modified within a single run.

## 2. The full run and per-stage status (measured by me)

Execution: `bash tests/haxe/alias-transfer-boundary/run.sh` (the script self-allocates a run directory and does not overwrite existing runs), evidence directory **`out/alias-transfer-boundary/runs/atb-Wn4rY37a`**.

**Directly read rc = 0** (`RUN_SH_RC=0`), summary verdict `verdict failed` (differences 0, not-reached 5, target-failures 2).

Toolchain (directly read in this round's identity stage): haxe 4.3.7, rustc/cargo 1.98.0, Dart 3.13.3, kotlinc-jvm 2.4.10 (JRE 21.0.12), Swift 6.2.4 (p09 swiftc shim, wrapper mode), OpenJDK 21/25.

Five targets per stage (each cell is the **directly read rc**; source `stages/<stage>/status`):

| stage | ts | kotlin | rust | swift | dart |
|---|---|---|---|---|---|
| gen | 0 | 0 | 0 | **1** | 0 |
| compile | 0 | 0 | **101** | **not-reached** (gen=1) | 0 |
| run | 0 | 0 | **not-reached** (compile=101) | **not-reached** (gen=1) | 0 |
| compare | identical(0) | identical(0) | **not-reached** (compile=101) | **not-reached** (gen=1) | identical(0) |

- oracle: `haxe-oracle-compile`=0, `haxe-oracle-run`=0 (5 shape rows), `haxe-oracle-expect` identical(0).
- Unreached stages are marked faithfully: rust's run/compare are unreached because `compile-rust=101`; swift's compile/run/compare are unreached because `gen-swift=1`. The script records them explicitly as `not_reached` rather than passing them off as semantic differences.
- `membership` (stage-check)=0, every declared stage has a record.

## 3. The three findings written separately

### 3.1 Observation of nullable unwrap (shape a, `field`)

`NullableHolder` is constructed with the original container, and `holder.values` (the nullable field slot) is read back as a `ReadOnlyArray<Int>` view; the retained mutable alias `original` then mutates `[0]=7` and pushes. The ts/kotlin/dart targets all print `field=702` in this round's measurements (7×100 + len 2): **the nullable field slot shares the original storage, and unwrap reads the post-call mutation**; no de-shared copy is observed (that would yield 101). The null control `fieldNull=0` passes in this round's measurements (the unwrap probe can read out an empty slot; it is not a constant). This is a measured conclusion for ts/kotlin/dart; rust/swift have **no target run readings** due to their respective generation/compilation defects (§2, fixes filed as separate rows `t-muovfs5q-5ht7` and the Swift storage decision row), so no extrapolation is made.

### 3.2 Observation of field rebinding (shape a, `fieldRebind`)

After the view is established, `holder.values = [9,8,7]` rebinds the field. ts/kotlin/dart all print `fieldRebind=123` in this round's measurements: **the already-established view retains the original storage (1,2,3) and does not follow the field's rebinding** (if it followed it would yield 987). That is, rebinding the field slot does not affect the identity of the already-unwrapped old view.

### 3.3 Observation of whether a mutable alias is retained after the call (shape b, `relay`)

`relayThrough(source)` passes the container in as a read-only argument and returns it unchanged; the caller's retained mutable alias mutates `source[0]=33` after the call. ts/kotlin/dart all print `relay=3301` in this round's measurements (33×100 + len 1): **both the argument position and the return position share the original container, and the call does not sever the path from the mutable alias to the relayed view** (a copy at either position would yield 1201). The fresh control `relayFresh=0` passes in this round's measurements (the relay probe can distinguish shared from non-shared).

## 4. Probe discriminating power: can this fixture fail

- **The semantic probes are discriminating**: each shape carries discriminating readings — the shared-read vs copy-read (702/101, 3301/1201) and view-retains vs follows-rebinding (123/987) take different values; and the three controls `fieldNull`, `relayFresh`, `fieldRebind` prove each probe is not pinned to a constant. If some target lowers the shared read into a copy (or the view follows the rebinding), the corresponding `compare-<target>` diff becomes nonzero, `compare-notes.txt` records the difference, and the summary verdict becomes `observed-differences`.
- **But run.sh itself is an observation fixture, not a gate**: the script's last statement is `cat "$RUN/summary.txt"`, with no `exit` statement after it and no `set -e`; the file header claims "Only failed and harness-defect exit nonzero", but stage-level failure only lands in the `VERDICT=failed` string — **in this round the measured verdict is failed while the directly read rc is still 0**. The script's only nonzero exit paths are the opening setup/fixture-missing case (`exit 1`) and the missing `.haxelib` dev pointer (`exit 2`). Therefore treating rc as a gate would always pass green; a gate consumer must read the `verdict` field in `summary.txt`.

## 5. rust / swift readings (measured in this round, consistent with the cited run)

Reproduced in this round's own run (measured by me, source `atb-Wn4rY37a`):

- **rust `compile-rust` = 101**: `error[E0308]: mismatched types`, at `atb/container_alias_oracle.rs:14:122` (expected u32, found usize; `v.len()` and the `map_or` default value `0` are inferred as u32 and mixed); diagnostic shape count `grep -cE '^error(\[E[0-9]+\])?:'` = 2 (1 E0308 + 1 "could not compile" summary line). **Fix filed as separate row `t-muovfs5q-5ht7`, out of scope for this task.**
- **swift `gen-swift` = 1**: `atb/ContainerAliasOracle.hx:44: characters 41-54 : swift target: array boundary has no prepared storage decision` (diagnostic shape count = 1). The emitter rejects loudly and produces no compilable tree. **Fix filed as a separate row, out of scope for this task.**

Cited cross-check: the previous run `atb-whb18ccE` (`out/alias-transfer-boundary/runs/atb-whb18ccE`) under the same fixture hashes gives exactly matching per-stage readings (ts/kotlin/dart matched, rust 101, swift gen 1, verdict failed) — this report does not re-cite its artifacts as evidence, using it only as a consistency corroboration.

## 6. How to reproduce

```
PATH=<haxe>/bin:<rust>/bin:<dart>/bin:<p09-swift-shim>:<kotlin>/bin:<jdk>/bin:<node>/bin:~/.bun/bin:$PATH \
HAXELIB_PATH=$PWD/.haxelib \
  bash tests/haxe/alias-transfer-boundary/run.sh
# artifacts in the auto-allocated out/alias-transfer-boundary/runs/atb-XXXXXXXX/ (summary.txt, status.tsv, stages/*/status)
```

This round's toolchain and hashes are recorded in the run directory `identity/` and `hashes.txt`; the consistent before/after input manifests reproduce that the fixture was not modified mid-way.
