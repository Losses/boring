# REANCHOR v2 — P08 reviews re-anchored to RECORD.md 445L (`21bce64b…`)

Date: 2026-09-30. Workspace: `/home/losses/Development/tq-workspace`.

## 1. Anchor verification (done first, both PASS)

| file | expected | measured |
|---|---|---|
| `dc-warn/out/boundary-policy-record/RECORD.md` | `21bce64b263dfb37c7b1082145a2e65b29f867c32fb45d62c0eec07daecc0a81`, 445 lines | identical, 445 lines |
| `dc-warn/out/boundary-policy-record/RECORD.before-correction-13.md` | `9886fe25c9c5ea392958b3ec2167c7903934d0f1593b25a7ae90633bba45b24e`, 390 lines | identical, 390 lines |

Evidence: `evidence/anchor-hashes.txt`.

## 2. Old→new line map — derived from the retained file, not inferred

**Statement of provenance: every mapping in `LINEMAP.tsv` was derived by running a real
diff (`difflib.SequenceMatcher`; raw opcodes and the per-line dict are in
`evidence/old2new.json`, full unified diff in `evidence/record-full.diff`) over the two
retained on-disk files whose hashes are verified above. Nothing was inferred, guessed, or
carried over from the earlier 367→390 pass.** For every cited line I also re-read the
content at the mapped coordinate to confirm it is the same text.

Diff structure (8 change sites, all inside §2/§3/§4/§6):

| change | old | new | nature |
|---|---|---|---|
| literal-null row scoping clause | 54 | 54 | CONTENT-CHANGED in place (clause appended) |
| three REFUSED rows scoping clauses | 57-59 | 57-59 | CONTENT-CHANGED in place |
| new §2 nil-merge-target row | — | 62 | INSERTED |
| CORRECTION 13 block | — | 115-146 | INSERTED |
| §3 boundary-plan producer row | 147 | 180 | CONTENT-CHANGED in place |
| §4 nil-merge-operands row | 188 | 221 | CONTENT-CHANGED in place |
| tryBindingLines §6 bullet | 339 | 372-379 | CONTENT-CHANGED (1 line → 7; tryReturnLines merged in + staleness note) |
| two new §6 open items | — | 393-407 | INSERTED |

Resulting shifts: old ≤61 → same; old 62-113 → +1; old 114-339 → +33 (with 147 and
188 changed in place at 180/221); old 340-352 → +40 within the 339 expansion region
(340→380); old 353-390 → +55.

Citation-by-citation mapping with content checks: **`LINEMAP.tsv`**.

## 3. What the SUPERSEDED citations' claims become

Only two citations are substantively superseded; everything else is STILL-VALID or pure
LINE-SHIFT (see LINEMAP.tsv).

1. **§0 pin + §8 item 6 + narrative (review lines 30, 35, 42-45, 558-562).**
   Claim "the record is 390 lines / `9886fe25…`, now frozen" is **now false as a
   current-state claim** (the record moved again to 445L/`21bce64b…`). The review's own
   history statements remain true as history. Fix: extend the pin, add the second move.
2. **`RECORD.md:58` as a flat "REFUSED" for the fixture cell (review line 372, O11 line
   ~492, ledger "blocked by … refusal cell").** CORRECTION 13 scopes row 58 as a
   **planner-cell refusal only**: as a nil-merge target the composition presents the
   optional intermediate destination (`destinationOptionalOverride = true`) and the cell
   converts via `MapOptionalMutableArrayView` (`SwiftArrayBoundary.hx:200-202`, verified).
   Concretely:
   - The review's argument "a refusal the acceptance fixture demands is an open defect on
     the decision axis" is **WEAKENED, not falsified**: the record now rules the
     nil-merge occurrence (which is exactly the fixture shape
     `values == null ? [] : values`), leaving the refusal standing only for callers that
     present a required destination unchanged (e.g. `SwiftDecl.hx:599` — verified: a
     two-argument `prepare`).
   - What is now **unresolved in the review** is route attribution: the review's [EXEC]
     abort (`SwiftExpr.hx` "array boundary has no prepared storage decision",
     `evidence/gen-ro-probe6.log`) was observed on a tree; if that tree already contained
     the candidate's `true` override at the nil-merge target (`SwiftExpr.hx:2646`,
     verified present in `swc-try-fix-wt/wt`), the observed refusal cannot have come from
     the nil-merge route and O11 must be re-attributed to a concrete route before it
     stands. **Not verified here** — blocker: the review's instrumented shadow log does
     not state which revision of `SwiftExpr.hx` it instrumented, and re-running the probe
     was out of scope for an anchoring pass.
   - The mechanism-level findings (split violated at coordinator layer, AST-derived veto
     at `SwiftArrayBoundary.hx:225`, plan-check gap) are **unchanged and still
     supported**; CORRECTION 13 does not touch them.

No review conclusion is made **false** by the update except the two current-state anchor
claims in (1); O11 is weakened pending route re-attribution.

## 4. Minimal revision lists

- **Behaviour review**: `REANCHOR-behaviour.diff` — 12 anchor substitutions, one pin
  extension, one narrative addendum, one scoping addendum at the row-58 citation, one
  re-worded O11 row. No conclusion deleted; nothing rewritten.
- **Implementation review**: `REANCHOR-implementation.diff` — **empty (no revision
  required).** Verified by grep: the file contains **zero citations to RECORD.md**; its
  only anchors are code/tree anchors (`SwiftExpr.hx bf7dde2c…` 7041L candidate,
  `SwiftArrayBoundary.hx b522865c…` unchanged, `SwiftDecl.hx 0210d207…` unchanged), none
  of which moved. One optional one-line §0 addition is offered, non-blocking.

## 5. Errors found in the new version's own text and citations

Code citations were checked against the actual compiler source at
`dc-warn/swc-try-fix-wt/wt/packages/compiler/reflaxe/swift/swiftcompiler/` — the tree
whose `SwiftArrayBoundary.hx` matches the record's own pinned sha `b522865c…` (verified)
and whose `SwiftExpr.hx` matches the P08 candidate anchor `bf7dde2c…` (verified). Raw
line dumps: `evidence/codeline-dump.txt`.

**Correct (verified):**
- `SwiftArrayBoundary.hx:173` — `destinationOptionalOverride` consumed into
  `destOptional` ✓; `:188` the `if (destOptional)` gate whose false branch leaves
  `operation` null ✓; `:189-191` `PreserveNullArrayValue` ✓; `:200-202`
  `MapOptionalMutableArrayView` ✓; `:207-208` `KeepPreparedArray` ✓; `:203`/`:221` empty
  `case OptionalOperand:` ✓; `:210` `OtherArrayStorage` ✓; `:212` mutable branch ✓;
  `:218-220` `MapOptionalReadOnlyIntoMutableArray` ✓; `:233-234` null return ✓;
  `:165` `prepare` signature with the override parameter ✓.
- `SwiftDecl.hx:599` — two-argument `prepare(operand, field.type)` ✓.
- `SwiftExpr.hx:2646` nil-merge target lowered with literal `true` ✓; `:2647` fallback
  lowered with the caller's `destinationOptionalOverride` ✓; `:2645` nil-merge branch ✓;
  `:2665-2666` ordinary-conditional required-destination guard ✓.
- `docs/compiler-policy-interfaces.md:171-173` — the quoted "optional intermediate
  destination" sentence is verbatim there ✓; `:155-157` the untouched planner rule ✓;
  `:176-177` the forbidden outcome the new §6 bullet cites ✓.
- `docs/investigations/architecture-round-1/j-prepared-value-design.md:135-137` ✓ (the
  record cites the file unqualified; it lives under `docs/investigations/architecture-round-1/`
  — acceptable, noted).
- `swift-checkpoint-todo.md:39-42` SW04 item ✓; `SwiftBoundaryPlanChecks.hx:54-62`
  fabricates the `ReadOnlyArrayView × optional` operand ✓.

**Errors / corrections:**

| # | record text says | actually (candidate tree) | severity |
|---|---|---|---|
| E1 | the candidate "inserts the `destinationValueText` funnel into both routes (`SwiftExpr.hx:5229` and `:5275`, in the candidate tree)" | `:5229` and `:5275` are the **function declaration lines** of `tryBindingLines`/`tryReturnLines`. The funnel calls are at **`:5253` and `:5267`** (tryBinding) and **`:5296` and `:5310`** (tryReturn). | WRONG LINES — correct to `:5253/:5267` and `:5296/:5310` |
| E2 | "falsifies this bullet and the sibling claim at `:339`" | `:339` in the 445-line file is **CORRECTION 13's own heading**. In the 390-line file `:339` was this very bullet. The intended sibling is the boundary-reference inventory bullet ending "none inside `expr`" — now at **`:367-371`** (also falsified by the candidate, and not marked stale). | WRONG SELF-REFERENCE — correct to `:367-371` and extend the staleness note to that bullet (its inventory `:4760/:4863/:2627-2628` are pre-candidate coordinates, see E3) |
| E3 | "the override axis is already live before the candidate, at the registered-default call-argument routes `SwiftExpr.hx:4760` and `:4863` (`true`)" | `true`-override call-argument routes sit at **`:4779` and `:4882`** in the candidate tree; 4760/4863 are pre-candidate (baseline) coordinates and are non-boundary lines in the candidate tree. Defensible as a deliberate "before the candidate" frame, but the same paragraph mixes in candidate-tree coordinates (`:2646`), so the frame is inconsistent. | STALE/INCONSISTENT — either label 4760/4863 as baseline coordinates or use `:4779/:4882` |
| E4 | "lowers the fallback against the final destination (`:2628`/`:2647`)" | `:2647` ✓; `:2628` in the candidate tree is `return fail(...)`. The fallback lowering exists only at `:2647`. | WRONG LINE — `:2628` should be dropped or given as its pre-candidate coordinate |
| E5 | §4 table (pre-existing, restated by CORRECTION 13 as "section 4 already registers the nil-merge operands that thread it (`SwiftExpr.hx:2627-2628`)") | in the candidate tree `:2627-2628` are `if (plan == null) / return fail(...)`; the nil-merge coordination is `:2646-2647`. 2627-2628 are baseline coordinates; CORRECTION 13's sibling sentence uses candidate coordinates for the same routes. | INTERNALLY INCONSISTENT frame — one coordinate system should be chosen and stated (the record's own §6 bullet already says "candidate" for `:2645-2658`, so candidate coordinates are the natural choice) |
| E6 | stale-bullet ranges "`tryBindingLines` (:5210-5250)" / "`tryReturnLines` (:5251-5287)" (now in three places: :372, :310, :411) | candidate-tree extents are `tryBindingLines` **`:5229-5273`** and `tryReturnLines` **`:5275-~5312`**; `:5251` lands inside `tryBindingLines`. The old ranges were baseline coordinates; the bullet claims to speak "in the candidate tree" for the funnel. | STALE — label as pre-candidate or renumber |

Nothing in the inserted §2/§3/§4 text is internally inconsistent with the surrounding
rows; row numbers cited inside the new table clauses (rows 54, 57-59, new row 62,
boundary-plan row, nil-merge row) are all correct in the new file.

## 6. Resulting pairing per review

- **Behaviour review** (`p08-behaviour-review/REPORT.md`, and the applied copy
  `review-reanchor-apply/REVIEW.reanchored.md`): after the edits in
  `REANCHOR-behaviour.diff` it should cite **`RECORD.md`, 445 lines,
  sha256 `21bce64b263dfb37c7b1082145a2e65b29f867c32fb45d62c0eec07daecc0a81`** (with the
  two superseded revisions 367L/`4d348992…` and 390L/`9886fe25…` kept in its history
  note).
- **Implementation review** (`p08-implementation-review/REPORT.md`): cites **no record
  revision**; pairing statement unchanged (code anchors only). If a record line must be
  named at all, name 445L/`21bce64b…` as "not cited by this review".

## 7. Reverse-direction check (new version vs the reviews)

- The two new §6 open items (`RECORD.md:393-407`) — destinationOptionalOverride
  reachability, and the nil-merge missing required-destination check — are **not cited
  by either review** (both postdate them). The behaviour review's O-list should gain a
  pointer once revised; neither review contradicts them.
- The record's CORRECTION 13 row-62 composition rule **does not contradict** the
  behaviour review's mechanism findings, but it does **contradict any reading of O11 as
  an end-to-end refusal for the nil-merge route** (§3 above).
- The record's new §6 staleness note (tryBinding/tryReturn falsified by the candidate)
  matches the implementation review's O1/O2 observations (try/tryReturn routes gained
  boundary consultation in the candidate) — consistent; the record correctly credits the
  finding to the freeze/record-cell pass, though the reviews documented it first.
- The record's inventory bullet (`:367-371`, "none inside `expr`") is left unmarked
  although the candidate also moves those coordinates — flagged as E2/E6.

## 8. Not verified

- Which revision of `SwiftExpr.hx` the behaviour review's [EXEC] shadow probe
  instrumented (needed to re-attribute O11's refusal to a route). Blocker: the probe log
  records no tree hash; re-execution was out of scope for an anchoring pass.
- Whether `docs/compiler-policy-interfaces.md:171-173` and the SW04 todo existed in the
  pre-candidate tree at the cited lines (checked in the candidate tree only — the tree
  the record pins by hash).

## 9. Files

- `LINEMAP.tsv` — per-citation old→new map
- `REANCHOR-behaviour.diff` — proposed minimal revision (behaviour review)
- `REANCHOR-implementation.diff` — no-revision assessment (implementation review)
- `evidence/` — `anchor-hashes.txt`, `record-full.diff`, `old2new.json`,
  `codeline-dump.txt`

No tracked file was modified; the record and both reviews are untouched.
