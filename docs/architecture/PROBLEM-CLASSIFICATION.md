# Cross-Target Problem Classification (A–F = Compiler Responsibilities)

This document groups the recurring failures across Boring targets (TypeScript, Kotlin, Rust, Swift, Dart)
into a limited set of **compiler responsibility** categories. The purpose of the classification is not counting, but answering one question:
**which layer owns a new failure, and therefore where it should be fixed and where it should be verified.**

## Basis of the Classification

The classification is drawn from existing records in this program, not invented:
the investigations in `docs/investigations/architecture-round-1/`, the two architecture consultations
(`dc-warn/out/sol-architecture-consult/{SOL2-ARCH-ANSWER.md,ASTRA-ANSWER.md}`),
`CODEX-AUDIT.md`, and the mechanisms of four fixes already applied in this session.

## A–F: Six Categories of Responsibility

| Category | Responsibility | Input facts | Owner | Typical symptom when crossing boundaries |
|---|---|---|---|---|
| **A** | **Source fact extraction** | Types, annotations, literals on the AST | Frontend | Treating unannotated inference as fact |
| **B** | **Representation choice** | What form the type takes in the target language | Target backend | Same Haxe type emitted in different forms at different sites |
| **C** | **Boundary conversion** | Whether wrapping/unwrapping is needed between source and target | Boundary layer | Missing or duplicate wrapping |
| **D** | **Destination derivation** | What type is needed at this position | **The composition that surrounds it** | Borrowing an unrelated return type (**see lambda defect**) |
| **E** | **Effects and lifetimes** | Evaluation count, laziness, aliasing, lifetime | Composition + backend | Repeated evaluation, alias mutation |
| **F** | **Diagnostics and suppression** | Whether generated code is legal, whether there are warnings | Backend | Warnings treated as acceptable |

## Why Category D Must Have an Explicit Owner (the core lesson of this session)

The mechanism of the lambda defect (`dc-warn/out/lambda-return-contract/`) is:
`currentReturnType` is the return type of the **member**, `functionLiteral` does not rebind it,
so every "return site" reads the type of the **outer function**.

**This is neither a category B (representation choice) error nor a category C (missing conversion):**
the conversion code itself is correct; what is wrong is **the destination it references**.

⇒ **The owner of category D is "the composition surrounding the position"**, not the surrounded expression,
nor the outer function. Sol's formulation: *"Composition owns intermediate requirements"*
(`docs/compiler-policy-interfaces.md:169`).

⇒ **Criterion**: if placing the same expression into different compositions yields different (but each correct) output,
then at that position the destination **must** be passed in by the composition and **must not** be inferred from global state.

## Known Instances Across Targets (mapping, not an inventory)

| Category | Instance | Location of record |
|---|---|---|
| A | Kotlin: consumer reads inferred facts instead of declared facts | ~~`out/kotlin-local-presence-facts`~~ worktree no longer exists; **evidence pending** |
| B | Rust: `String` vs `UString` host string representation | commit `40cf0ad0` |
| B | Swift: `[Int32] = Array(...)` vs `ReadOnlyArray<Int32> = ReadOnlyArray(...)` | commit `9c9548ef` |
| C | Swift: read-only array boundary wrapping (SW04) | ~~`out/sw04-fix-wt`~~ worktree no longer exists; **evidence pending** |
| D | Swift: lambda return contract borrows member type | commit `d14aae11` (**with regression, see below**) |
| D | Swift: `switchExpression` derives destination from `sw.t` | ~~`out/switchexpr-destination` (in progress)~~ worktree no longer exists; **evidence pending** |
| E | Swift: `switchStatement` strips arm `return` ⇒ control-flow error (W1) | commit `d14aae11` |
| F | All targets: warnings counted as acceptance (standard `:78`/`:80`) | recorded at TCN-156 |

**Two forms of `out/...`, opposite empirical results (2026-10-01)**:

| Form | Example | Result |
|---|---|---|
| **Path inside worktree** `dc-warn/out/...` | `dc-warn/out/sol-architecture-consult/` | **exists** |
| **Bare worktree name** `out/...` | the three entries in the table above | **none exist** |

The two look the same, but in reality one refers to **files in a long-lived directory** and the other to **the temporary worktree itself**.
The former survived because it lives inside `dc-warn`; the latter vanishes when the worktree is cleaned up, leaving no trace.

**Two kinds of reliability for recorded locations (empirically verified 2026-10-01)**:

| Form | Spot-check result |
|---|---|
| Commit hashes (`40cf0ad0`, `9c9548ef`, `d14aae11`) | **all three present** (`git cat-file -t` = commit) |
| `out/...` worktree names (three entries) | **all three absent** |

The three `out/` names are `out/kotlin-local-presence-facts`, `out/sw04-fix-wt`,
`out/switchexpr-destination`; searched under `/home/losses/Development/tq-workspace` by directory name,
branch name, and worktree name — **none found**. Among them `out/sw04-fix-wt` differs from the actually existing
`sw04-xcheck-local` by only a few characters and is easily mistaken for verified.

**This does not mean those instances do not exist** — they record facts observed at the time, and the commit hashes remain verifiable.
What has failed is the **"where to look"** column: worktrees get cleaned up, and cleanup leaves no trace, so references to worktrees
**silently expire**, and after expiring still read as "verifiable".

**Rule (addendum)**: when recording instances, prefer **commit hashes** — commits do not disappear, worktrees do.
If a worktree reference is unavoidable, also write down the **observed output or evidence** so the row remains verifiable after the directory vanishes.
Status words like `(in progress)` are especially dangerous: they assert a **present-tense** fact, and the document lies the moment it goes out of sync.

## Rules for Using the Classification

1. **Locate the category first, then the site.** Reporting only "file X line Y is wrong" does not count as locating.
2. **A fix at one site must not change behavior in another category.** All four committed fixes were verified with full generated-tree diffs;
   byte-identical output is a **necessary condition**.
3. **The category owner and the site location can differ** (category D is exactly this case) —
   that is precisely why explicit contracts are needed.
4. **Failure classification must carry attribution**: candidate responsibility / pre-existing repository state / missing documentation
   (lesson recorded at P10, `out/p10-reflection/ACCEPTANCE-REFLECTION.md`).

## Not Yet Covered by This Classification

- **Category G (tentative name): uniqueness of criterion source**. A–F classifies "**which piece of code is responsible for what**",
  but this item asks "**how many sites independently decide the same thing**". Empirical: Rust's `state.shimsUsed`
  has **28 write sites** (3 files) and **12 read sites** (that gate emission), with **no contract** governing who must write;
  it is simultaneously treated as "business code referenced an extern" (intent) and "should a resident be emitted" (emission),
  **the two layers are not equivalent** ⇒ modules declared in `runtime/mod.rs` were never emitted (`E0583`).
  This is a **cross-cutting** category: it can appear inside any of A–F, hence **not suitable** to squeeze into A–F;
  already recorded as **contract 6** in `ARCHITECTURAL-CONTRACTS.md`; this section only registers the classification gap.- **Category J migration** failures (legacy Kotlin → Haxe) are not classified into A–F;
  CODEX-AUDIT notes "complete J migration were not established".
- **Naming consistency** (ReadOnlyArray naming violation) — whether it belongs to F or a separate category, not yet decided.
- The instance table for each target is **incomplete**: it only lists those with records in this session,
  not an inventory of all known failures per target.

## What This Classification **Deliberately Excludes**: Process/Integrity Issues (see `LAYERED-VERIFICATION.md`)

A–F in this document is a classification of **compiler responsibilities** (which piece of code is responsible for what).
The things this session has repeatedly paid a price for are **not compiler responsibilities**, hence **not here**,
but in two sections of `LAYERED-VERIFICATION.md` — to avoid writing the same rule twice:

- **Criteria must state "on which tree they hold"** (the newly added L0 front section of that file): the same artifact gives
  **opposite conclusions** on two trees — the hardened guardrail had been reviewed and signed off yet was **never an ancestor of base**, so the weak version runs on base:
  deleting the real root + a one-word rationale `"because"` still gets **rc=0 PASS**, while the hardened version gives rc=1 and names it verbatim.
  With the three-step verification method (branch exists / is it an ancestor of base / **directly read the shared tree** — the third step is the one that catches it).
- **Delivery surface: load-bearing artifacts must be able to answer "which commit contains it"** (same file): tools, guardrails, fixtures, drivers,
  assertion scripts must be checked in; empirically verified that under `dc-warn/worktrees/` **37/37** are all detached and none carries a commit beyond `e1c65975`,
  and the evidence manifest included **git-ignored** paths, making "one command rc=0" **only valid for the author's working copy**.
- **"Which tool to use" and "which diagnostics are visible" must be explained separately** (see `ARCHITECTURAL-CONTRACTS.md` contract 3 supplement).
  This is **adjacent but at a different angle** to **category F** (warnings counted as acceptance) of this document: category F asks "should it be counted",
  this asks "can this command **see** it" (`swiftc -typecheck` reports 0 even in baseline state ⇒ relying only on the type-checker turns zero warnings into a vacuous criterion).