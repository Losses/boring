# SHA and Int64 Workplan

## Purpose

Add portable SHA-256 and SHA-512 support to the boring translatable subset.
The implementation uses the existing `haxe.Int64` standard type as the one
64-bit integer capability. Target output uses native representations and
operations, runtime stays minimal, compiler changes use structured AST and
typed information, and every capability has cross-target evidence.

## Non-negotiable decisions

1. `haxe.crypto.Sha256` and `haxe.crypto.Sha512` accept `haxe.io.Bytes` only. Text encoding is outside the hash API.
2. PHP and Java branches are removed from the portable source. No PHP or Java-specific crypto API is required.
3. No external crypto dependency is added. Every target has a boring-translated portable implementation.
4. TypeScript may use a synchronous host-native bridge for Node, Bun, and Deno only when the selected host entry provides one. Browser output uses the synchronous portable implementation. Web Crypto async APIs are out of scope.
5. `haxe.Int64` is the reusable fixed-width 64-bit platform capability. No second `BigInt`, word, or SHA-specific integer type is added.
6. `haxe.Int64` is independent of `float-precision` and wire float widths. It is supported by every target even when a target chooses a native crypto bridge for SHA.
7. Target mappings use native 64-bit storage where available: TypeScript `bigint`, Rust native 64-bit integers selected by operation semantics, Kotlin `Long`, Swift native 64-bit integers selected by operation semantics, and Dart `int` subject to verified 64-bit semantics.
8. Simple Int64 operations lower directly to target expressions. Wrapping addition, logical shifts, bitwise operations, constants, high/low extraction, and fixed rotations avoid runtime helpers when the target can express them directly.
9. V11 changes from a file-path allowlist into capability validation. It rejects unsupported Int64 APIs or unsafe crossings by typed AST semantics and never admits a test or algorithm by file name.
10. `Bytes` remains the Haxe source API. Rust lowering distinguishes borrowed input (`&[u8]`), mutable internal storage, and owned output (`Vec<u8>`). Haxe does not expose Rust lifetimes.
11. `BytesBuffer` remains the growable sink. Hash block buffers and digest outputs use fixed-size byte storage where the target can represent it directly.
12. Compiler implementation is AST-first. No string search, regex rewrite, or ad hoc target-expression concatenation may implement a new language feature. Existing fixed runtime source templates are allowed only for independent runtime source; AST lowering uses structured data.
13. Every new capability has Haxe/stage-one evidence and generated, compiled, and executed tests for every supported target. Hash output comparisons are byte-for-byte.
14. Performance is the primary target criterion. Cross-platform consistency defines observable semantics while generated code may use a different native shape on each target.

## Stages

### Stage 0: Specification and baseline

- [x] Record this workplan in the repository.
- [x] Rewrite the Int64, byte capability, numeric, runtime, style, testing, and SHA specifications for the single Int64 architecture.
- [x] Update the specification index.
- [x] Run the existing verification baseline and record failures without changing unrelated code.

### Stage 1: haxe.Int64 platform capability

- [x] Replace the V11 file-path allowlist with typed capability validation.
- [x] Define the supported Int64 constructors, operators, high/low extraction, constants, and boundary conversions.
- [x] Add direct target mappings for TypeScript, Rust, Kotlin, Swift, and Dart.
- [x] Implement 64-bit wrapping, logical shift, and rotate semantics through structured target lowering.
- [x] Add Int64 capability samples and cross-target tests independent of SHA.
- [x] Verify both `float-precision=f64` and `float-precision=f32` where the target supports both.

### Stage 2: Bytes capability

- [ ] Complete fixed-length `Bytes` declarations and target lowerings for allocation, read, write, copy, fill, and output conversion.
- [ ] Define read-only input, mutable internal storage, and owned output in the target ABI.
- [ ] Add byte capability tests for aliasing, copying, bounds, and ownership-sensitive Rust signatures.
- [ ] Keep runtime additions limited to operations that cannot be emitted directly.

### Stage 3: Portable SHA implementations

- [ ] Add `Sha256` with `Bytes`-only one-shot and incremental APIs.
- [ ] Add `Sha512` using `haxe.Int64` with no compiler module-name special cases.
- [ ] Remove PHP/Java branches and string-based exception throws from the portable source.
- [ ] Keep block processing and padding in source code that passes the boring subset rules.
- [ ] Define and test message-length behavior, including the 128-bit SHA-512 length field.

### Stage 4: Host optimization

- [ ] Add a TypeScript host bridge that is isolated from browser output.
- [ ] Select native synchronous crypto only in Node/Bun/Deno host entries where available.
- [ ] Keep browser and all non-JS targets on portable generated code under the no-dependency rule.
- [ ] Test that browser bundles do not statically import Node-only modules.

### Stage 5: Cross-target generation and verification

- [ ] Add generation entries for SHA and Int64 probes to all supported targets.
- [ ] Compile generated TypeScript, Rust, Kotlin, Swift, and Dart code with their native toolchains.
- [ ] Run common NIST vectors and incremental chunking vectors on every target.
- [ ] Run the full repository verification suite.
- [ ] Update this plan after each completed stage and only mark a stage complete after its tests pass.

## Required hash vectors

- Empty input.
- `abc`.
- Inputs of lengths 55, 56, 63, 64, 65 for SHA-256.
- Inputs of lengths 111, 112, 127, 128, 129 for SHA-512.
- Input spanning more than one block.
- Incremental updates using different chunk boundaries.
- One-shot and incremental output equality.
- Int64 values with high bit set, zero, all bits set, carry across the low word, and every SHA rotation distance.

## Context recovery rule

After context compaction, read this file first. The non-negotiable decisions
and the stage checklist are authoritative. Continue from the first unchecked
item in the current stage, inspect the working tree, and update the checklist
immediately after each verified milestone. Continue only from the recorded
architecture and do not replace a pending item with a narrower shortcut.

## Current status

Stage 1 is complete. Int64 lowers to native target operations on TypeScript,
Rust, Kotlin, Swift, and Dart; the same source tests pass on all default
configurations and on the Rust, Kotlin, and Swift f32 configurations. Stage 2
starts with fixed-length Bytes allocation, mutation, copy, fill, and ownership
rules. No SHA implementation work begins until the Bytes stage passes its
cross-target tests.
