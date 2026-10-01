# P08 CANDIDATE FREEZE RECORD

**Object:** the combined Swift-backend compiler patch `INTEGRATION.diff` applied to the
coordination tree `boring-wt-architecture`, together with the two focused fixtures, the
discriminating route fixtures, the governing acceptance record, and the toolchain identity.

**Frozen at:** 2026-09-30T03:55:40-04:00 (America/Toronto), by recomputation on the live
workspace. Every number below is either **[MINE]** (I recomputed or executed it in this
session) or **[QUOTED]** with the named source. The two are never blended.

**Status in one line:** the *implementation* is now pinnable and reproducible byte-for-byte;
the *acceptance* is **not complete** — obligation 1 is unverified by its designated reviewer,
obligation 2 fails the literal "zero diagnostics" requirement, obligation 3 is executed-clean
but one of its named dimensions (branches distinguishable by execution) is not testable with
the fixture as written, and the *governing acceptance record has already drifted past the
first review that cites it*.

---

## 0. Why this record exists, and what it does not settle

Consultation obligation (ASTRA-ANSWER.md:22, sha256 `9beeeaeab830d30bb943cd10a256898836670e316bd2fb240ec15803b596c77f`) **[QUOTED]**:

> "Freeze implementation, fixtures, governing acceptance record, configuration, and input
> identities together. One review judges semantic expectations and discriminating coverage;
> the other judges implementation ownership, routing, composition, and actual evidence.
> Both review the same candidate and both must accept."

This record discharges the **freezing** half: it gives both reviews one addressable object.
It does **not** accept the candidate, and it does not substitute for either review.

Two claims in that obligation are satisfied by this record: implementation + fixtures +
record + configuration + input identities are now pinned together (bundle hash, §6).
One claim is **not** yet satisfiable: the two reviews cannot cite the same object today,
because the governing record moved after review 1 was written (§4) and review 2 has no
report (§5.0).

---

## 1. Candidate implementation identity **[MINE]**

### 1.1 Coordination tree (the frozen base), recomputed

| item | value |
|---|---|
| path | `/home/losses/Development/tq-workspace/boring-wt-architecture` |
| HEAD | `e1c6597514634fd347d392709793cc19bd96c9a2` |
| HEAD subject | `merge: integrate fix/rust-readonly-alias-emitter (0701762d) into Rust fix candidate` (2026-09-29 12:32:46 -0400) |
| branch | `arch/agent-guided-governance` |
| clean/dirty | **DIRTY** |
| dirty-file count | **25** entries = **15 modified** + **10 untracked** |
| whole-tree content hash | `986807b22188952e8cd469907cc1407ab0b4378af748322f0f8344d0a43e301e` (5440 files; sha256 of the sorted `<sha256>  <path>` manifest; excludes `.git`, `out`, `node_modules`) |

The 25 dirty entries and their individual sha256 are listed in full in
`evidence/01-coordination-tree.txt`. **The freeze base is not a commit** — it is a working
state. This matters: `git checkout` of HEAD would NOT reproduce the frozen object, because
15 tracked files carry uncommitted edits, two of which (`SwiftArrayBoundary.hx`,
`SwiftDecl.hx`) are the Swift boundary mechanism this candidate builds on.

### 1.2 The patch, and confirmation that it touches exactly one file

`INTEGRATION.diff` sha256 `e67ab1a47de29432671394604b551af05945f3609a2a1ee6efa9bedbf2d03a3c` (10831 bytes)
`MANIFEST.md` sha256 `fa3082540cbfc10ee5f1f61f2320b2c594efbd70d80b0fea737068c06d4d6cb2`
`REPORT.md` sha256 `a799f5330f71559a89195b226601619e10a479ed571f9b1acde6dda0ca6679fe`

Recomputed from the diff itself, not taken from the manifest:

| quantity | measured |
|---|---|
| `diff --git` file headers | **1** |
| files touched | **1** — `packages/compiler/reflaxe/swift/swiftcompiler/SwiftExpr.hx` |
| hunks (`@@`) | **13** |
| added / removed lines | **+55 / −15** |
| non-Swift files touched | **0** |

**Verified, not assumed:** the one-file claim was checked by reading the diff (`grep -c '^diff --git'` → 1;
the only `---`/`+++` pair names `SwiftExpr.hx`), and independently by the whole-tree delta in §2.

### 1.3 The one touched file, both sides

| artifact | sha256 | bytes |
|---|---|---|
| `SwiftExpr.hx` **at coordination base** (unpatched) | `0a9bed91ef91ca68b75a2e7e4e2482d2743a16fe5caf4150018686c2131e33f0` | 328711 |
| `SwiftExpr.hx` **candidate** (patched) | `bf7dde2cec3b89464738019c733eb6f1d8e666bbc976176bf30cc77007be6078` | 331720 |

The base hash matches, independently, the anchor the behaviour review recorded
(`p08-behaviour-review/evidence/identity.txt`) **[QUOTED, and reproduced MINE]**.

---

## 2. Verified state, and reproduction from the patch **[MINE]**

Recipe, executed in `/tmp` (the coordination tree, the patch and every test were left
untouched):

```
rsync -a --exclude=.git --exclude=out --exclude=node_modules \
  boring-wt-architecture/ /tmp/p08-freeze/verify-apply/
cd /tmp/p08-freeze/verify-apply
patch -p1 --dry-run < dc-warn/out/integration-manifest/INTEGRATION.diff
patch -p1          < dc-warn/out/integration-manifest/INTEGRATION.diff
```

Exit codes captured **directly from `patch`**, never through a pipe:

| step | exit code |
|---|---|
| `patch -p1 --dry-run` | **0** (`checking file .../SwiftExpr.hx`) |
| `patch -p1` (real apply) | **0** (`patching file .../SwiftExpr.hx`) |
| `cmp` result vs `dc-warn/swc-try-fix-wt/wt/.../SwiftExpr.hx` | **0** (byte-identical) |
| `*.orig` / `*.rej` left behind | none |
| `diff -rq` patched copy vs `swc-try-fix-wt/wt` (excl `.git`/`out`/`node_modules`) | **0 differing entries** |

**Answer to the question asked:** yes — applying `INTEGRATION.diff` to a fresh copy of the
coordination tree reproduces the verified worktree's patched `SwiftExpr.hx` **byte-for-byte**,
and the whole tree matches the verified worktree with exactly one file differing from base.

Reproduction is confirmed a second way, at tree level:

| tree | content hash |
|---|---|
| coordination tree (base) | `986807b22188952e8cd469907cc1407ab0b4378af748322f0f8344d0a43e301e` |
| candidate tree (base + `INTEGRATION.diff`) | `b75c8c0f2470aa620a1945f874b96a8bf023eb31eb38c56066c013f956cf5262` |
| delta between the two 5440-file manifests | **exactly one line** — `SwiftExpr.hx` |

### 2.1 A note on `PATCH.diff`

`dc-warn/swc-try-fix-wt/PATCH.diff` sha256 `7b10df6ee667a2a306b629b7724fbbd9a41b5f0fdac167b527730bf1715fe86b`.
It is **not byte-identical** to `INTEGRATION.diff` (plain-`diff` header vs `diff --git` header,
plus different context-line suffixes). The added/removed line multisets are identical
(70 sign lines each: 55 added, 15 removed). The decisive check is the applied result above,
which is byte-exact. Do not treat the two files as interchangeable *as files*; their end
states are equal.

---

## 3. Fixtures, configuration and input identities **[MINE]**

Full listings are in `evidence/03-fixtures.txt`; the headline pins:

### 3.1 Archived counterexample fixture and its generated Swift

| artifact | sha256 |
|---|---|
| `dc-warn/out/gap-fixture-archive/fixture/gap/Gap.hx` | `150315585b0a4aee5df5d1f9f24e217a2c5f747717aa6161eb1032769b057048` |
| `.../fixture/swift-archived.hxml` (the archived driver) | `72624696f51a14db37f349a7aa78e1b7ff00a9e2ddfccf705d36d6ee835ad3de` |
| `.../generated/gap/Gap.swift` (**the archived, PRE-patch output**) | `01cbbb8193f73c095eb05a24c8874e7366399194e8bd607ec9e50073779b227b` |
| `.../generated-repro/gap/Gap.swift` | `01cbbb8193f73c095eb05a24c8874e7366399194e8bd607ec9e50073779b227b` (identical) |
| `.../generated/Runtime.swift` | `a24d5fa3f7ec5fec2732fd671598b348a494268bcb1e63a178c5266373587795` |
| `.../generated/std/UStringException.swift` | `ca9b248766df8131cd04dabfbba9976dd56ad7c021f3718e658681356297c0a4` |
| `.../generated/std/UStringFault.swift` | `36499cfbd939a8f73e1d00ae030c74f4e58007898a9beb74410b69ce7ba40b3e` |
| archive self-check `FILES.sha256` | 51 entries, **51 OK / 0 FAILED** when I ran `sha256sum -c` |

**Important distinction.** The archived generated Swift is the **defective, pre-patch** tree.
**I proved this rather than assuming it:** generating the same fixture from a fresh copy of the
unpatched coordination tree yields `01cbbb8193f73c095eb05a24c8874e7366399194e8bd607ec9e50073779b227b` — identical to the archive.
Generating it from the candidate yields a **different** file,
`2be5e102d695146439d3fdab3c1aeee7f8096d7d1460b92fd9535055c70c02ab` **[MINE]**, which is also
byte-identical to the tree the second (implementation) review generated independently at
`/tmp/p08ir/out/gap-fixed/gap/Gap.swift` **[MINE, cross-check]**. The archive therefore holds
the counterexample, not the repaired output; there is **no retained artifact of the repaired
`Gap.swift`** in the archive.

### 3.2 Acceptance fixture sources (`tests/swift-readonly-boundary/`, coordination tree)

All 7 files; the worktree copy is byte-identical (verified file by file):

| file | sha256 |
|---|---|
| `swift.hxml` | `e891207150c71f3656c19a3da1f21e84f5b80f7fc8ec0e8a4230d27411f9762a` |
| `oracle.hxml` | `c1b6abdcd474da8227460aa24e84f6725f620aea3367a193cd41e19ac4d8f801` |
| `readonly-boundary.test.ts` | `1fe2f482ce4b10a689538720b59c0da2c2f925b693bf6da85ec0ff6e7e57ce54` |
| `ReadOnlyBoundaryRuntimeTests.swift` | `11511b36b4a29ceca74be6ca985d7e6ddb54fce8a521fe7da6a340c10ae7c2c2` |
| `boring/ReadOnlyBoundaryOps.hx` | `edcdf4f5edb79d05badcf29fb1d717698f9ac263bb7f7ba1272fb3b04741e966` |
| `boring/ReadOnlyBoundaryOracle.hx` | `12d5a005580b171bddd95e6e5a6d5dd5ce2ffb4a287d37cc26b8c6b344cf3953` |
| `boring/SwiftBoundaryPlanChecks.hx` | `789f42d734fc459e3262b8b5414ec6326b108f6e340bd3740c84056152efb6db` |

(`tests/` is an empty directory — there are no files under it.)

**This directory is the configuration** for the acceptance run as much as the sources:
`swift.hxml` fixes the `-cp` set, the boundary plan-check macro, and the runtime imports.

### 3.3 Discriminating route fixtures (`dc-warn/out/route-fixtures/fixtures/`)

21 files, classes c1/c2/c3 plus negative controls; every sha256 is in
`evidence/03-fixtures.txt`. Entry points:

| fixture | driver | positive source |
|---|---|---|
| c1 (try binding/return) | `c1-try/swift.hxml` `bb69866cdb723b2ebfe157e127aae0b82d927a48aa5ec66fa4a29ca78e523588` | `c1-try/boring/C1TryOps.hx` `096d6bb75f8155aedaf6f690b04ab031d914f50ea0995ab6b73ef609543f2f55` |
| c2 (switch binding/expression) | `c2-switch/swift.hxml` `4ee70af86e956164472a9adf5d1a713f2d7c4f736f0e0916a12eaa99112030c2` | `c2-switch/boring/C2SwitchOps.hx` `c1ca5b33dc09457704169f5015f9324cd3b10175b8bbfe0b70493e869190cb15` |
| c3 (switch assignment) | `c3-assign/swift.hxml` `49641ba916b5eb94b1d6a44d8dff11075f40da8e5856cba0201bcffc39a81658` | `c3-assign/boring/C3AssignOps.hx` `938be43f1f921558e5316b2acad4f742a1163604e53d5130d8b71d0bb4932550` |

Their **pre-patch generated Swift and swiftc stderr** are retained in
`dc-warn/out/route-fixtures/evidence/` (hashes and per-file diagnostic counts recomputed in
`evidence/03-fixtures.txt`). Those retained trees are the **RED** state — see §5.2.

### 3.4 Compiler toolchain identity

| item | value |
|---|---|
| PATH source | `dc-warn/out/chainA-fixed-rerun/evidence/env.json`, sha256 `c221c6f7a860b16c9ebdae141fbf8c346d62315d637058d4a40245a2ec7b9e52` |
| **type of that file** | **plain text `KEY=VALUE` lines, NOT JSON** — confirmed by reading it (no braces, no quoting); 57 PATH entries |
| haxe | **4.3.7**, `/nix/store/98pb92k7pi6g5cifmg872jn18kghaxw5-haxe-4.3.7/bin/haxe` |
| swiftc | **Swift version 6.2.4 (swift-6.2.4-RELEASE)**, `Target: x86_64-unknown-linux-gnu` |
| swiftc resolution | PATH[0] is a shim: `p09-chainA-work/swift-shim-bin/swiftc` sha256 `d5842a5dabf19b94e48feaba50f690316e389adc6250842f8edcbd36db50e221`, which execs `/nix/store/j1bfa7mw323wmp6pfrn1qkchxv61wk2n-swift-toolchain-6.2.4-al2/usr/bin/swiftc` |
| shim state | `SWIFT_SHIM_STATE = p09-chainA-work/swift-shim-state-fixed3` |
| haxelib | `HAXELIB_PATH = boring-wt-architecture/.haxelib` (provides `boring`, `reflaxe`) |

**Do not cite a stale artifact for this.** `dc-warn/out/gap-fixture-archive/evidence/swiftc-version.log`
(sha256 `4da4443592359895cf6edce10ab7db640a146ffbbad32d7156a060526855e535`) does **not** contain a
version; it contains a failed invocation
(`.../swift-6.2.4-fhs-fhsenv-rootfs/usr/bin/swiftc: No such file or directory`). The identity
above is measured, not copied.

Also note: invoking the shim prints a host-side
`<unknown>:0: warning: libc not found for 'x86_64-unknown-linux-gnu'` line for some commands.
That is a shim/SDK-state diagnostic about the host, **not** a compiler diagnostic about
generated code; the acceptance typecheck below produced a completely empty stderr.

---

## 4. The governing acceptance record — and the fact that it has drifted **[MINE + QUOTED]**

The governing record for this candidate is `dc-warn/out/boundary-policy-record/RECORD.md`
(the policy record that fixes the approved producer families, destinations, presence and
retained facts).

| item | value |
|---|---|
| **measured now** | **390 lines, 26384 bytes, mtime 2026-09-30 03:06:50 -0400** |
| sha256 | **`9886fe25c9c5ea392958b3ec2167c7903934d0f1593b25a7ae90633bba45b24e`** |

### 4.1 Drift chain

| revision | source |
|---|---|
| 131 lines | "both review reports identify" — **[QUOTED] `CODEX-ARCH-ANSWER.md:5`** |
| 186 lines | CODEX consult's first read — **[QUOTED]** |
| 279 lines / `0ac047d6c34ae12fc8a9fad2f7d8da6810213a45d950b7b44bdb0d5203976eaf` | CODEX's second read + `boundary-review-v3` — **[QUOTED]** |
| 362 lines | behaviour review's first read — **[QUOTED] `p08-behaviour-review/REPORT.md:36`** |
| 367 lines / `4d34899236b9db0d84cc97637f13930d42c299435fd57c3ca01a82223cb63dd7` | what the **behaviour review pinned** — **[QUOTED] `REPORT.md:30`** |
| **390 lines / `9886fe25…`** | **[MINE], measured 03:55** |

### 4.2 Consequence for the two-review requirement

The behaviour review was written at **02:31**. `RECORD.md` was rewritten at **03:06** —
*after* the review. Every RECORD citation in that review (its §0 anchor table and every
Q-section that quotes the record) therefore refers to a revision that no longer exists at
that path. A second review written now would necessarily cite `9886fe25…`. **The two reviews
cannot currently be said to cite the same governing record**, which is exactly the condition
the consultation's freeze clause exists to prevent.

### 4.3 A material contradiction between the record and the candidate **[MINE]**

`RECORD.md:58` (current revision) still declares this cell **REFUSED**:

> **Citation note (REVERTED).** An independent cross-check (F2) reported this row at `:56` and the
> coordinator amended this record accordingly. **That was wrong and has been reverted.** The
> ruled row — `MutableArrayWrapper` x read-only-position x optional-source-to-required-dest — is at
> **`:58`**; `:56` is the **`OtherArrayStorage`** row, which is a *different* row and is correctly
> left as it stands (its empty case fires regardless of any destination override, so it genuinely
> is an end-to-end refusal).
>
> **How the error arose, recorded because it is a reusable lesson:** the coordinator located the
> row by grepping for `OtherArrayStorage` — a keyword that belongs to row `:56`. The keyword hit
> the *wrong row*: the row under discussion is the `MutableArrayWrapper` row at `:58`. A second
> independent check (`override-ruling-xcheck`) caught this and verified the ruling's original `:58`
> citation as exact. **Keyword-hit row is not the discussed row.**

> `MutableArrayWrapper` × read-only position × **optional source → required dest** → REFUSED:
> the empty `case OptionalOperand:` (`SwiftArrayBoundary.hx:203`) leaves `operation` null.

The candidate makes that cell succeed for the nil-merge route, by an explicit override:
`SwiftExpr.hx:2646` now reads

> **Citation correction (found by the independent specification ruling, verified by the
> coordinator against the candidate tree):** this record (and the dispatch that produced it)
> cited the forced override at `:2647`. **It is at `:2646`** — `:2647` is the *fallback* arm,
> which correctly keeps the caller's `destinationOptionalOverride`. Verified by reading the
> candidate tree: `:2646 targetValue = lowerArrayBoundary(nilMerge.target, target, null, true)`.
`lowerArrayBoundary(nilMerge.target, target, null, true)`. In `prepare`,
`destOptional` is `destinationOptionalOverride == null ? isOptionalType(destinationType)
: destinationOptionalOverride` (`SwiftArrayBoundary.hx:171`), so the forced `true` selects
`case OptionalOperand if (destOptional): MapOptionalMutableArrayView`
(`SwiftArrayBoundary.hx:201-202`) instead of falling through the empty case to a refusal.

So the record's absolute "REFUSED / `prepare` returns null" claim is no longer true for at
least one live caller, and the record has **no row for the override input** and **no
CORRECTION for this change**. This is **not automatically a code defect** — the override is
precisely what makes the required-destination nil-merge composition (optional arm + literal
fallback) legal, and it is what unblocks acceptance-fixture generation. But it is an
**unruled** change to a decision the governing record states as settled, and it must be
ruled on (record revised, or the override documented as a distinct input) before obligation 1
can be judged. It is listed as open in §7.

---

## 5. Obligation map — what the retained reports actually establish

The three P08 obligations are quoted from `SOL2-ARCH-ANSWER.md:87-89`
(sha256 `5b53acad68da832da55321f139192e914fcdd0c202fb2cf8c8e0c16d7e8acdd4`) **[QUOTED]**.
Verdict vocabulary: **sufficient** = the obligation's own wording is met on this candidate by
retained evidence; **partial** = something measurable is green but the wording is not met.
"A report exists" is not treated as "the obligation is met".

### 5.0 Which reviews exist

| review | role (per ASTRA) | state |
|---|---|---|
| `p08-behaviour-review/REPORT.md` sha256 `27d54a3fd87deab087794c2f78ad119865c2ffb2188be712285da672fb80e61a`, 577 lines, written 02:31 | semantic expectations + discriminating coverage | **delivered** |
| `p08-implementation-review/` | implementation ownership, routing, composition, actual evidence | **NOT DELIVERED.** `PROGRESS.md` checklist items 4–8 unchecked; `evidence/` holds in-flight logs timestamped 03:39–03:54; **no `REPORT.md` exists**. It was still writing while this record was made. |

### 5.1 Obligation 1 — Correct fact and requirement handoffs — **PARTIAL, not sufficient**

Required by its wording: the **implementation review** covers the approved producer
families, actual destinations, intermediate requirements, valid presence and retained facts;
**in-scope reconstruction is removed**.

- **The designated verifier has not reported.** SOL2 assigns this obligation to the
  implementation review; as of this record, that review has produced only scratch evidence.
  This alone prevents a "sufficient" verdict.
- **"In-scope reconstruction is removed" is demonstrably not achieved.** The only completed
  review documents at least five live re-derivations of facts from AST types or printed text
  (`SwiftExpr.hx` sites `:2048` `nilMergeChainNonOptional` parsing printed `" ?? "`,
  `:1203`, `:1966`, `:5525`, `:4349-4355`, `:5492-5515`) **[QUOTED behaviour review Q4/Q6]**.
  The candidate removes none of them. Concretely, from the patch text I read myself **[MINE]**:
  - `switchAssign` **still** reconstructs the assignment by rewriting printed lines:
    `final marker = indent(depth + 2) + "return "; … if (StringTools.startsWith(lines[i], marker)) …`.
    The patch only changes which destination the arms were converted against
    (`switchReturn(sw, depth, true, target.t)`); the string surgery remains the mechanism.
  - `armLines` still derives its boundary decision from AST types (`returnValue.t`, `s.t`).
  The retained `armlines-separability/REPORT.md` (sha256 `c159ea34fc926675747ee2da74cd64345c6ec332f2e7d46c2fc3fc8be0c1641d`) reaches the same
  conclusion independently on the **patched** tree **[QUOTED]**: cause 2 (string surgery)
  is "**PRESENT**, and now harmless — but still **load-bearing as plumbing**".
  Making the spliced text correct is a real improvement; it is not removal of reconstruction.
- **What *is* established (positive, [MINE]).** The three named route classes now carry an
  actual destination. I generated and typechecked c1/c2/c3 against the candidate: each is
  `gen rc=0` and `swiftc -typecheck rc=0` with **0 errors / 0 warnings**, versus the author's
  retained pre-patch readings of **4 / 2 / 2 errors** (see §5.2). So the *handoff now happens*;
  what is missing is the reviewed account that it is *correct at every approved producer family*
  and that the reconstruction is gone.
- **The record contradiction in §4.3** is squarely inside this obligation and is unruled.

**Verdict: PARTIAL. Not sufficient.** Blocker: the designated review has not reported, and
its own subject matter (reconstruction removal) is falsified by the patch text.

### 5.2 Obligation 2 — Legal generated output — **PARTIAL: the error axis is met, "zero diagnostics" is NOT**

Required by its wording: both focused fixtures generate successfully; native compilation
succeeds with **zero diagnostics** on those same candidate inputs.

Measured by me on the candidate, directly (never through a pipe; full detail in
`evidence/05-my-reruns.txt`):

| focused fixture | generation | `swiftc -typecheck` | errors | warnings |
|---|---|---|---|---|
| acceptance (`tests/swift-readonly-boundary/`) | **rc=0** | **rc=0**, stderr **0 bytes** | **0** | **0** |
| counterexample (`gap`, archived fixture) | **rc=0** | **rc=0** | **0** | **2** |

The acceptance fixture is genuinely clean: 0 errors **and** 0 warnings, empty stderr.

The counterexample fixture is **not** clean. The candidate output
`gap/Gap.swift` (sha256 `2be5e102d695146439d3fdab3c1aeee7f8096d7d1460b92fd9535055c70c02ab` **[MINE]**)
still emits, verbatim:

```
gap/Gap.swift:113:17: warning: result of 'ReadOnlyArray<Element>' initializer is unused [#no-usage]
gap/Gap.swift:115:17: warning: result of 'ReadOnlyArray<Element>' initializer is unused [#no-usage]
```

**Does this affect the obligation? Yes — strictly, it defeats it.** The obligation is stated
over "those same candidate inputs", not over "the diagnostics this patch caused". Two
diagnostics are two diagnostics. Two further points make this more than pedantry:

1. **The warning is not cosmetic; it marks a real behavioural defect.** The function is
   `GapExplicitReturn.switchExplicitReturn`: both switch arms evaluate their value and
   discard it, then the function unconditionally returns `Gap.sourceFirst()`. The variant
   intended to return `sourceSecond()` returns the wrong value. I verified **[MINE]** that
   this function is **byte-identical** in the base and candidate generated trees (the full
   `diff -u` of the two generated `Gap.swift` files is in §7's evidence and touches only the
   crossing sites), and that the base emits the same two warnings — so the defect is
   **pre-existing and untouched** by the patch. But the obligation is about the *input*, and
   the input still contains it.
2. **The archive's own success criterion is still unmet.** `gap-fixture-archive/README.md:89-91`
   defines the "Correct state" as `swiftc -typecheck` exiting 0 "with zero `Gap.swift`
   diagnostics". Under the candidate there are still two `Gap.swift` diagnostics. **[MINE,
   against the quoted archive text]**

The error axis is genuinely closed: **12 errors → 0 errors**, and the fingerprint
(42, 56, 58, 68, 70, 79, 81, 93, 129, 131, 140, 142) is eliminated **[MINE, reproduced]**;
both fixtures generate **[MINE, reproduced]**; and the second review independently reproduced
`gen rc=0` / `typecheck rc=0` plus the same two warnings in its in-flight evidence **[MINE,
read from `p08-implementation-review/evidence/`]**.

There is also a **collection** precondition attached to this obligation **[QUOTED
`SOL2-ARCH-ANSWER.md:91`]**: "the focused tests must enter a routine repository command and
CI, with their expected membership demonstrated." Not delivered: the behaviour review
verified by code that CI runs only `test:*` scripts and never `bun run test`
(`.github/workflows/ci.yml:35,135,199` vs `package.json:9`), and the acceptance test aborts
before its Swift half (§5.3). The gap fixture is collected by nothing at all outside
`dc-warn/`.

**Verdict: PARTIAL. The error axis is met on both fixtures; the literal zero-diagnostics
requirement is met on one of the two and failed on the other, and durable collection is
absent.** The 2 warnings do affect the obligation.

### 5.3 Obligation 3 — Preserved source behaviour — **PARTIAL: execution verified, one named dimension untestable, collection red**

Required by its wording: typed downstream uses **and execution distinguish both branches**,
null/default outcomes, shared alias mutation, retained lifetime, single evaluation, lazy
effects, control exits.

Measured by me on the candidate (full output in `evidence/05-my-reruns.txt`):

| step | result |
|---|---|
| interpreter oracle (`haxe tests/swift-readonly-boundary/oracle.hxml`) | rc=0, **30 lines** |
| generation | rc=0 |
| `swiftc -typecheck` (5 generated + tracked shim) | rc=0, stderr 0 bytes |
| `swiftc -o` build | rc=0, stderr 0 bytes |
| run binary | rc=0, **30 lines** |
| diff runtime vs oracle, line for line | **identical (rc=0)** |

That single run covers, by expectation line: **shared alias mutation** (`alias=7:2`),
**retained lifetime** (`reference=11:true:17:true`), **single evaluation / lazy effects**
(`effect=1:8:1`), **null/default outcomes** (`nullable-elements`, `nullable-literal-elements`,
`nullable-local-literal-elements`, `present-optional`, `absent-optional`, `guarded-present`,
`guarded-absent`, `guarded-field`, `coalesced-null`, `coalesced-present`, `default-omitted`,
`default-null`, `default-present`, `nullable-fallback-omitted`, `nullable-fallback-null`,
`nullable-fallback-present`, `guarded-nullable-fallback`, `null-reassigned`), and
**typed downstream uses** (`direct-call`, `constructor`, `field-assignment`, `static-field`,
`return`, `enum`).

**Two things stop this being sufficient.**

1. **"Execution distinguish both branches" is NOT testable with the fixture as written, and
   is not established.** The adjudication
   `dc-warn/out/branch-expectation-ruling/REPORT.md` (sha256 `cd110bed6833943346bb6bca3e0a41be4dab0c5e745f7ea8d41090841f42f513`)
   shows that `branchBoundary(true)` and `branchBoundary(false)` are observationally
   **identical** (`1:present` either way), because the consumer prints only the length plus a
   constant suffix; a backend that always took one branch would pass that line **[QUOTED, and
   the oracle output `branch-true=1:present` / `branch-false=1:present` is reproduced MINE]**.
   The obligation names "distinguish both branches" explicitly. It is therefore **not
   discharged by this fixture**, and no alternative fixture is retained that does discharge it.
2. **The collected test cannot run, and its expectation is wrong.** The tracked expectation in
   `readonly-boundary.test.ts` is `branch-true=1:1` / `branch-false=2:1`; the oracle produces
   `1:present` / `1:present` **[MINE, reproduced]**. The test therefore fails at its **oracle
   step** and never reaches its `swiftc` or zero-diagnostics assertions. The ruling
   (sha256 `cd110bed…`) reached the same conclusion and adds that the expectation is wrong "at
   birth" (a template copy-paste, introduced together with the fixture in squash commit
   `e5e21854`) **[QUOTED]**. My manual pipeline above is the only route by which the Swift half
   was exercised at all.
3. **Control exits are only partially probed, and the gap fixture — which does exercise a
   control exit — is never executed.** The campaign typechecks the gap fixture but never runs
   it (behaviour review §8.5 **[QUOTED]**); and the one control-exit shape it contains
   (`switchExplicitReturn`) is the W1 defect of §5.2, which returns the wrong branch.

**Verdict: PARTIAL.** Execution of the acceptance fixture is genuinely green and matches the
interpreter oracle line-for-line; the obligation's explicit "distinguish both branches"
dimension is unmet, and the collecting test is red.

### 5.4 Obligation-to-report ledger

| obligation | retained report that measured it | what was measured | sufficient? |
|---|---|---|---|
| 1 | `p08-behaviour-review/REPORT.md` **[QUOTED]**; `armlines-separability/REPORT.md` **[QUOTED]** on the patched tree | fact/producer census; 5 live re-derivations; string surgery still present | **no — partial** |
| 1 | `p08-implementation-review/` | — | **not delivered** |
| 2 | `integration-manifest/MANIFEST.md` §4a/§4b + `REPORT.md`; `p08-implementation-review/evidence/*` | both fixtures gen rc=0; typecheck rc=0 / 0 errors / 2 warnings; acceptance 0 diagnostics | **no — partial** |
| 2 | `gap-fixture-archive/REPORT.md` + `expected-outcomes.md`; `route-fixtures/` + `route-fixtures-xcheck/` | pre-patch RED state and defect fingerprints | context only |
| 3 | `integration-manifest` runtime run; `branch-expectation-ruling/REPORT.md` | 30/30 oracle lines matched; branch lines indistinguishable; expectation wrong | **no — partial** |

---

## 6. The single hash a reviewer should cite

### 6.1 The freeze hash (cite this for "the same candidate")

```
FREEZE-BUNDLE = b664c91cd09ba6b80517e809feca90a7995f68b84b81589126fed525da1a3878
```

**Recipe (recomputable by anyone):** take `evidence/06-freeze-manifest.sha256` — 47 lines of
the form `<sha256>  <symbolic-key>`, sorted by key with `LC_ALL=C sort -k2` — and run
`sha256sum` over that file. The file and the recipe are both in this directory.

**What it covers:** the coordination tree HEAD and dirty-entry count; the whole-tree content
hash of the coordination tree and of the candidate tree; the patched and base `SwiftExpr.hx`;
the four Swift backend mechanism files; `INTEGRATION.diff`; the gap fixture source and its
archived generated Swift; all seven acceptance-fixture files; all 21 route-fixture sources;
the toolchain `env.json` and the swiftc shim; `RECORD.md`; the work plan; and the two
consultation answers that state the obligations and the freeze clause.

**What it does NOT cover — read this before quoting it:**

- It does **not** assert that any obligation is met. It pins identity, not acceptance.
- It does **not** include the other 23 dirty coordination-tree entries, nor any of the 5440
  individual files beyond the two tree-level content hashes. The tree-level hashes *do* cover
  all 5440 files, but only as a single aggregate; per-file detail is in
  `evidence/01-coordination-tree.txt` and `evidence/08-coord-tree-content.sha256`.
- It does **not** pin the *correctness* of any expectation, and specifically not the stale
  `branch-*` expectation that makes the acceptance test red.
- It does **not** pin the generated output of the two focused fixtures under the candidate
  (that output is not retained anywhere); it pins only the authoritative acceptance-file
  hashes and the archived pre-patch counterexample.
- It does **not** cover the reports that verify the candidate; they are pinned individually
  in §5 and in `evidence/` but are outside the bundle.
- It is a hash of a **dirty working tree**. Any further uncommitted edit inside
  `boring-wt-architecture` changes the tree hash and therefore this bundle. Recompute before
  citing if the tree may have moved.

### 6.2 The implementation hash (cite this for "the patched file")

```
bf7dde2cec3b89464738019c733eb6f1d8e666bbc976176bf30cc77007be6078   SwiftExpr.hx (candidate)
```

This is the sole file `INTEGRATION.diff` changes, and it is **byte-for-byte reproducible** from
the frozen base plus the patch (§2). It is the right hash to quote when the point being made
is about the *code under review*. It does not cover the fixtures, the record, or the toolchain.

### 6.3 What a reviewer must NOT do

Do not cite a hash for `RECORD.md` taken from an earlier report: `4d348992…` (367 lines, the
behaviour review's pin) is **superseded**; the live file is `9886fe25…` (390 lines) (§4).

---

## 7. Not verified / open / stale — the honest remainder

**Unverified because not run:**

1. **Full `bun test tests/` — never run by anyone quoted here.** Blocker stated by the
   manifest **[QUOTED]**: the `tests/ts/package-artifacts.test.ts` trap hollows the tracked
   `samples/boring/MathNaNTestSupport.hx`; plus a broad unrelated surface. I did not run it.
2. **`bun test tests/swift-readonly-boundary/` — not run by me, and it cannot pass as it
   stands.** It exits 1 at the oracle step on the stale `branch-*` expectation (§5.3). Until
   the expectation is corrected (or the test revised to actually distinguish the branches),
   the Swift half of this obligation has no collector.
3. **Route-fixture negative controls not re-run by me.** I re-ran the three positives only.
   The negatives are **quoted** green in `readings.tsv` / `route-fixtures-xcheck/REPORT.md`
   (`0/0/0` each); I did not reproduce them.
4. **Other targets not rebuilt.** Kotlin, Rust, TS and Dart generation/builds were not
   exercised. There is no regression data for them, although `INTEGRATION.diff` touches no
   non-Swift file and the whole-tree delta is one Swift file (§2).
5. **Compiler unit/self tests** (`tools/`, root `bun test`) not run.
6. **The compiler's own build** was exercised only implicitly (both fixtures generated, which
   compiles the Swift backend through haxe). No explicit compiler build/test target was run.
7. **The gap fixture is never executed** — only typechecked. Its runtime behaviour is
   unobserved, and its one control-exit shape is the W1 defect (§5.2).
8. **Second independent review (implementation) — not delivered.** In flight at 03:39–03:54;
   `PROGRESS.md` has 5 of 8 items unchecked and no report exists (§5.0). Until it lands, the
   two-review requirement cannot be met.

**Open defects and unruled changes:**

9. **W1 — `switchExplicitReturn` swallows `return`** (2 warnings, `Gap.swift:113/115`).
   Confirmed unchanged by the patch: the whole function is byte-identical base vs candidate,
   and the base emits the same 2 warnings **[MINE]**. This is the reason obligation 2 is not
   literally met, and it is also a genuine wrong-result defect on a control exit.
10. **The REFUSED-cell contradiction (§4.3).** The candidate converts a cell the governing
    record declares REFUSED, by an override the record does not model. Unruled.
11. **Reconstruction not removed** — the `switchAssign` printed-`return` rewrite still stands
    (§5.1). This blocks obligation 1 on its own wording.
12. **`RECORD.md` has drifted past the first review** (§4.2). The governing acceptance record
    is not itself frozen; it moved 367 → 390 lines at 03:06, after the behaviour review.
13. **The archive's `swiftc-version.log` is a failed invocation**, not a version (§3.4) — a
    stale artifact in the retained evidence set.
14. **No retained artifact of the candidate-generated `Gap.swift` or of the candidate
    acceptance generation.** Both exist only as transient `/tmp` trees; I hashed them at
    freeze time (`2be5e102…`, and the acceptance tree hashes in `evidence/05-my-reruns.txt`),
    but nothing in the repository retains them.
15. **Documented expectation mismatch of counts:** `swc-try-fix-wt/PROGRESS.md` says the
    acceptance runtime matched "29 lines"; the manifest and my own run say **30** **[MINE]**.
    The oracle emits 30 lines and 30 matched. Treat 30 as measured; 29 is a stale statement.

**Stale expectations in flight:**

16. **`readonly-boundary.test.ts` `branch-true=1:1` / `branch-false=2:1`** — wrong, reproduced
    by me, adjudicated, fix supplied as `CANDIDATE.diff` in the ruling directory, **not applied**
    (this record did not modify any test).

---

## 8. Provenance discipline

- **[MINE]** marks everything I computed or executed in this session: HEAD, dirty count, all
  file hashes, the tree content hashes, the patch-application exit codes, the bundle hash,
  the oracle run, both fixture generations, both typechecks, the build and runtime run, and
  the route-fixture re-runs.
- **[QUOTED]** marks statements taken from a named retained report, always with its path and,
  where it matters, its sha256.
- No number in this record is a blend of the two. Where a quoted number and my own measurement
  disagree, both are shown and the disagreement is named (e.g. 29 vs 30 lines, §7.15).
- Raw material: `evidence/01-coordination-tree.txt`, `02-patch-application.txt`,
  `02a/02b` patch logs, `03-fixtures.txt`, `04-toolchain.txt`, `05-my-reruns.txt`,
  `06-freeze-manifest.sha256`, `06-freeze-bundle.sha256`,
  `07-governing-records.txt`, `08-coordination-tree-content.sha256`,
  `09-candidate-tree-content.sha256`.

**Nothing in the coordination tree, the patch, or any test was modified.** All application and
generation ran in `/tmp` copies; the coordination tree's `SwiftExpr.hx` still hashes
`0a9bed91…` after all my work **[MINE]**.
