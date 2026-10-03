# Cross-Target Problem Classification (A–F = Compiler Responsibilities)

This document maps recurring failures across Boring targets (TypeScript, Kotlin, Rust, Swift, Dart)
to a finite set of **compiler responsibilities**. The purpose of classification is not statistics, but to answer one question:
**Which layer should own a new failure, and therefore where it should be fixed and where it should be verified.**

## Basis of Classification

The classification is drawn from existing records of this programme, not newly invented:
the investigation in `docs/investigations/architecture-round-1/` (2026-10-03 clearance migration, fact extraction noted in wb task t-muso22y0-5hn2 note), the two-seat architecture consultation
(`dc-warn/out/sol-architecture-consult/{SOL2-ARCH-ANSWER.md,ASTRA-ANSWER.md}`),
`CODEX-AUDIT.md` (now located in the archive `boring-docs-archive/evidence/ledger-cited-reports/p12-programme-review-evidence/evidence/consult/`), and the mechanisms of four defects already fixed in this session.

## The Six Categories A–F

| Category | Responsibility | Input Facts | Owner | Typical Symptom When Boundaries Are Crossed |
|---|---|---|---|---|
| **A** | **Source Fact Extraction** | Types, annotations, literals on the AST | Frontend | Treating unannotated inference as fact |
| **B** | **Representation Choice** | What shape the type takes in the target language | Target backend | Same Haxe type emitted in different shapes at different positions |
| **C** | **Boundary Conversion** | Whether wrapping/unwrapping is needed between source and target | Boundary layer | Missing wrapping or duplicate wrapping |
| **D** | **Destination Inference** | What type this position needs | **The composition that surrounds it** | Borrowing an unrelated return type (**see lambda defect**) |
| **E** | **Effect & Lifetime** | Evaluation count, laziness, aliasing, lifetime | Composition + backend | Duplicate evaluation, alias mutation |
| **F** | **Diagnostics & Suppression** | Whether generated code is valid and warning-free | Backend | Warnings treated as acceptable |

## Why Category D Must Have a Clear Owner (Core Lesson of This Session)

The mechanism of the lambda defect (`dc-warn/out/lambda-return-contract/`):
`currentReturnType` is the return type of the **member**; `functionLiteral` does not rebind it,
so every "return site" reads the type of the **outer function**.

**This is neither a Category B (representation choice) error nor a Category C (missing conversion) error:**
the conversion code itself is correct; what is wrong is **the destination it references**.

⇒ **The owner of Category D is "the composition that surrounds the position"**, not the surrounded expression,
nor the outer function. Sol's formulation: *"Composition owns intermediate requirements"*
(`docs/compiler-policy-interfaces.md:169`).

⇒ **Criterion**: if placing the same expression in different compositions yields different (but each correct) outputs,
then at that position the destination **must** be passed in by the composition and **must not** be inferred from global state.

## Known Instances Across Targets (Mapping, Not an Inventory)

| Category | Instance | Record Location |
|---|---|---|
| A | Kotlin: consumer reads inferred facts instead of declared facts | ~~`out/kotlin-local-presence-facts`~~ worktree no longer present; **evidence needed** |
| B | Rust: `String` vs `UString` host string representation | commit `40cf0ad0` |
| B | Swift: `[Int32] = Array(...)` vs `ReadOnlyArray<Int32> = ReadOnlyArray(...)` | commit `9c9548ef` |
| C | Swift: read-only array boundary wrapping (SW04) | ~~`out/sw04-fix-wt`~~ worktree no longer present; **evidence needed** |
| D | Swift: lambda return contract borrows member type | commit `d14aae11` (**with regression, see below**) |
| D | Swift: `switchExpression` derives destination from `sw.t` | ~~`out/switchexpr-destination` (in progress)~~ worktree no longer present; **evidence needed** |
| E | Swift: `switchStatement` strips arm `return` ⇒ control flow error (W1) | commit `d14aae11` |
| F | All: warnings counted as acceptance (standard `:78`/`:80`) | recorded TCN-156 |

**Two ways of writing `out/...`, opposite results when tested (2026-10-01):**

| Writing | Example | Result |
|---|---|---|
| **Path inside worktree** `dc-warn/out/...` | `dc-warn/out/sol-architecture-consult/` | **exists** |
| **Bare worktree name** `out/...` | three places in the table above | **none present** |

They look the same, but in practice one refers to **files in a long-lived directory** and the other to **the temporary worktree itself**.
The former survived because it resides inside `dc-warn`; the latter disappears when the worktree is cleaned up, leaving no trace.

**Two kinds of reliability for record locations (tested 2026-10-01):**

| Form | Spot-check result |
|---|---|
| Commit hash (`40cf0ad0`, `9c9548ef`, `d14aae11`) | **all three present** (`git cat-file -t` = commit) |
| `out/...` worktree names (three places) | **none of the three present** |

The three `out/` names are `out/kotlin-local-presence-facts`, `out/sw04-fix-wt`,
`out/switchexpr-destination`; searched under `/home/losses/Development/tq-workspace` by directory name,
branch name, and worktree name — **none found**. Among them, `out/sw04-fix-wt` differs from the actually present
`sw04-xcheck-local` by only a few characters, making it easy to mistake as verified.

**This does not mean those instances do not exist** — they record facts observed at the time, and the commit hashes remain inspectable.
What has failed is the **"where to look"** column: worktrees get cleaned up, and cleanup leaves no trace, so references pointing to worktrees
**fail silently**, and after failure still read as "verifiable".

**Rule (added)**: when recording instances, prefer **commit hashes** — commits do not disappear, worktrees do.
If a worktree reference is unavoidable, also write down the **observed output or evidence**, so the row remains checkable after the directory disappears.
Status words like `(in progress)` are especially dangerous: they assert a **present-tense** fact, and once the document goes out of sync they lie.

## Rules for Using the Classification

1. **Locate the category first, then the site.** Reporting only "some file, some line is wrong" does not count as localisation.
2. **A fix at one place must not change the behaviour of another category.** All four committed fixes performed full tree-of-generated-output comparisons;
   byte-for-byte identity is a **necessary condition**.
3. **The owner of a category can differ from where the site physically resides** (Category D is exactly this case) —
   this is why explicit contracts are necessary.
4. **Failure classification must carry attribution**: responsibility of the candidate / pre-existing repository state / missing documentation
   (lesson recorded from P10, published in `docs/architecture/ACCEPTANCE-REFLECTION.md` §2,
   publication commit `ec4c5c2d` — that file was deleted on 2026-10-03 during the process-document clearance, traceable via the commit; the earlier draft path `out/p10-reflection/` has been superseded by that publication).

## What This Classification Does Not Yet Cover

- **Category G (provisional name): uniqueness of criterion source**. A–F classifies "**who is responsible for one piece of code**",
  but this item asks "**how many places independently judge the same thing**". Observed: Rust's `state.shimsUsed`
  has **28 write sites** (3 files) and **12 read sites** (gating emission), with **no contract** specifying who must write;
  it is simultaneously treated as "a business reference to some extern" (intent) and "whether some resident should be emitted" (emission),
  **the two layers are not equivalent** ⇒ modules declared in `runtime/mod.rs` were never emitted (`E0583`).
  This is a **cross-cutting** category: it can appear inside any of A–F, so it is **not suitable** to squeeze into A–F;
  it has been recorded as **Contract 6** in `ARCHITECTURAL-CONTRACTS.md`; this section only registers the classification gap.- **Category J migration** (legacy Kotlin → Haxe) failures are not classified into A–F;
  CODEX-AUDIT notes "complete J migration were not established".
- **Naming consistency** (ReadOnlyArray naming violation) — whether it belongs to F or is a separate category has not been decided.
- The instance table for each target is **incomplete**: it only lists those recorded in this session,
  not an inventory of all known failures per target.

## What This Classification **Deliberately Excludes**: Process/Integrity Issues (See `LAYERED-VERIFICATION.md`)

A–F in this document is a classification of **compiler responsibilities** (who is responsible for one piece of code).
The matters this session repeatedly paid the price for are **not compiler responsibilities**, so they are **not here**,
but in two sections of `LAYERED-VERIFICATION.md` — to avoid writing the same rule in two places:

- **Criteria must state "on which tree they hold"** (the new L0 preamble section added to that file): the same thing yields
  **opposite conclusions** on two trees — the hardened guardrail was reviewed and signed off but was **never an ancestor of base**, so base runs the weak version:
  deleting the real root + the one-word rationale `"because"` still **rc=0 PASS**, while the hardened version rc=1 and names it verbatim.
  With a three-step verification method (branch exists / is ancestor of base / **read the shared tree directly** — the third step is the one that catches it).
- **Delivery surface: load-bearing artefacts must answer "which commit contains it"** (same file): tools, guardrails, fixtures, drivers,
  assertion scripts must be checked in; tested `dc-warn/worktrees/` — **37/37** all detached with none carrying commits beyond `e1c65975`,
  and the evidence checklist mixed in **git-ignored** paths, making "one command rc=0" **only hold for the author's working copy**.
- **"Which tool" and "which diagnostics that tool can see" must be stated separately** (see `ARCHITECTURAL-CONTRACTS.md` Contract 3 supplement).
  This is **adjacent to but at a different angle from** Category F (warnings counted as acceptance) in this document: Category F asks "should it be counted",
  this asks "can this command **see** it" (`swiftc -typecheck` reports 0 even in baseline state ⇒ relying solely on the type-checker turns zero warnings into an empty criterion).
