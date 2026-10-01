# Cross-Target Problem Classification (A–F = Compiler Responsibilities)

This document categorizes recurring failures across Boring targets (TypeScript, Kotlin, Rust, Swift, Dart)
into a limited set of **compiler responsibilities**. The purpose of this classification is not statistics, but answering one question:
**Which layer should own a new failure, and therefore where should it be fixed and where should it be verified.**

## Basis of Classification

The classification is drawn from existing records of this project, not newly invented:
investigations under `docs/investigations/architecture-round-1/`, two architectural consultations
(`dc-warn/out/sol-architecture-consult/{SOL2-ARCH-ANSWER.md,ASTRA-ANSWER.md}`),
`CODEX-AUDIT.md`, and the mechanisms of several defects fixed in this session.

## Six Categories of Responsibility A–F

| Category | Responsibility | Input Facts | Owner | Typical Symptom When Crossing Boundary |
|---|---|---|---|---|
| **A** | **Source Fact Extraction** | Types, annotations, literals on the AST | Frontend | Treating unannotated inference as fact |
| **B** | **Representation Selection** | What form the type takes in the target language | Target Backend | Same Haxe type emitted in different forms at different positions |
| **C** | **Boundary Conversion** | Whether wrapping/unwrapping is needed between source and target | Boundary Layer | Missing wrapping or duplicate wrapping |
| **D** | **Destination Derivation** | What type this position requires | **The composition enclosing it** | Borrowing an unrelated return type (**see lambda defect**) |
| **E** | **Effects and Lifetimes** | Evaluation count, laziness, aliasing, lifetimes | Composition + Backend | Repeated evaluation, alias mutation |
| **F** | **Diagnostics and Suppression** | Whether generated code is legal, has warnings | Backend | Warnings treated as acceptable |

## Why Category D Must Have a Clear Owner (Core Lesson of This Session)

The mechanism of the lambda defect (`dc-warn/out/lambda-return-contract/`) is:
`currentReturnType` is the return type of the **member**, `functionLiteral` does not rebind it,
so all "return position" sites read the type of the **outer function**.

**This is neither a Category B (representation selection) error nor a Category C (missing conversion):**
the conversion code itself is correct; what is wrong is **the destination it refers to**.

⇒ **The owner of Category D is "the composition enclosing that position"**, not the enclosed expression,
nor the outer function. Sol's formulation: *"Composition owns intermediate requirements"*
(`docs/compiler-policy-interfaces.md:169`).

⇒ **Criterion**: If placing the same expression in different compositions yields different (but each correct) output,
then at that position the destination **must** be passed in by the composition and **must not** be inferred from global state.

## Known Instances by Target (Mapping, Not Inventory)

| Category | Instance | Record Location |
|---|---|---|
| A | Kotlin: consumer reads inferred facts instead of declared facts | `out/kotlin-local-presence-facts` |
| B | Rust: `String` vs `UString` host string representation | commit `40cf0ad0` |
| B | Swift: `[Int32] = Array(...)` vs `ReadOnlyArray<Int32> = ReadOnlyArray(...)` | commit `9c9548ef` |
| C | Swift: read-only array boundary wrapping (SW04) | `out/sw04-fix-wt` |
| D | Swift: lambda return contract borrows member type | commit `d14aae11` (**with regression, see below**) |
| D | Swift: `switchExpression` derives destination from `sw.t` | `out/switchexpr-destination` (in progress) |
| E | Swift: `switchStatement` strips arm `return` ⇒ control flow error (W1) | commit `d14aae11` |
| F | All: warnings counted in acceptance (standard `:78`/`:80`) | recorded TCN-156 |

**Reliability of record locations falls into two categories (verified 2026-10-01)**:

| Form | Spot-Check Result |
|---|---|
| Commit hashes (`40cf0ad0`, `9c9548ef`, `d14aae11`) | **All three present** (`git cat-file -t` = commit) |
| `out/...` worktree names (three entries) | **All three absent** |

The three `out/` names are `out/kotlin-local-presence-facts`, `out/sw04-fix-wt`,
`out/switchexpr-destination`; searched under `/home/losses/Development/tq-workspace` by directory name,
branch name, and worktree name — **none found**. Among them, `out/sw04-fix-wt` differs from the actually existing
`sw04-xcheck-local` by only a few characters, making it easy to mistake as verified.

**This does not mean those instances do not exist** — they record facts observed at the time, and the commit hashes remain verifiable.
What is broken is the **"where to look"** column: worktrees get cleaned up, and cleanups leave no trace, so references pointing to worktrees
will **fail silently**, and after failure they still read as "verifiable".

**Rule (added)**: When recording instances, prefer **commit hashes** — commits do not disappear; worktrees do.
If a worktree reference is unavoidable, also record **the observed output or evidence**, so the row remains checkable after the directory disappears.
Status words like `(in progress)` are especially dangerous: they claim a **present-tense** fact, and the document lies as soon as it goes out of sync.

## Rules for Using the Classification

1. **Locate to a category, then to a site.** Reporting only "line N in file X is wrong" is not localization.
2. **A fix at one site must not change behavior of other categories.** Four committed fixes all underwent full generation tree comparison,
   byte-for-byte identical is a **necessary condition**.
3. **The owner of a category may differ from where the site is located** (Category D is such a case) —
   this is precisely why explicit contracts are needed.
4. **Failure classification must carry attribution**: candidate responsibility / existing repository state / missing documentation
   (lesson recorded in P10, `out/p10-reflection/ACCEPTANCE-REFLECTION.md`).

## Not Yet Covered by This Classification

- **Category G (tentative name): Uniqueness of Criterion Sources**. A–F classify "**who should own a given piece of code**",
  but this item asks "**how many distinct places each decide the same thing**". Observed: Rust's `state.shimsUsed`
  has **28 write sites** (3 files) and **12 read sites** (gating emission based on it), **no contract** specifying who must write;
  it is simultaneously treated as "business code references an extern" (intent) and "whether a resident should be emitted" (emission),
  **two layers not equivalent** ⇒ modules declared in `runtime/mod.rs` were never emitted (`E0583`).
  This is a **cross-cutting** category: it can appear inside any of A–F, and is therefore **not suitable** to stuff into A–F;
  it has been recorded as **Contract 6** in `ARCHITECTURAL-CONTRACTS.md`; this section only registers the classification gap.
- **Category J migration** (legacy Kotlin → Haxe) failures are not categorized into A–F;
  CODEX-AUDIT notes "complete J migration were not established".
- **Naming consistency** (`ReadOnlyArray` naming violation) — whether it belongs to F or a separate category, not yet decided.
- The **instance table** by target is **incomplete**: only those recorded in this session are listed,
  not an inventory of all known failures across targets.

## Intentionally NOT Covered: Process/Integrity Categories (Go to `LAYERED-VERIFICATION.md`)

The A–F categories in this document classify **compiler responsibilities** (who should own a given piece of code).
The items this session repeatedly paid for are **not compiler responsibilities**, and are therefore **not here**,
but in two sections of `LAYERED-VERIFICATION.md` — to avoid writing the same rule twice:

- **Criteria must state "on which tree they hold"** (the newly added L0 preamble section in that file): the same thing yields
  **opposite conclusions** on two trees — the hardened guardrail was reviewed and signed off but was **never an ancestor of base**,
  so base runs the weak version: delete the real root + one-word rationale `"because"` still **rc=0 PASS**, while the hardened version rc=1 and names it verbatim.
  Includes the three-step verification method (does the branch exist / is it an ancestor of base / **directly read the shared tree** — the third step is the one that actually catches it).
- **Delivery surface: load-bearing items must answer "which commit contains it"** (same file): tools, guardrails, fixtures, drivers,
  assertion scripts must be checked in; observed: `dc-warn/worktrees/` **37/37** all detached and none carry a commit beyond `e1c65975`,
  and the evidence list included **git-ignored** paths, making "one command rc=0" **only true for the author's working copy**.
- **"Which tool to use" and "what diagnostics are visible" must be explained separately** (see `ARCHITECTURAL-CONTRACTS.md` Contract 3 supplement).
  It is **adjacent to but differs in angle from** this document's **Category F** (warnings counted in acceptance): Category F asks "should it be counted",
  this asks "can this command **see** it" (`swiftc -typecheck` reports 0 even in baseline state ⇒ trusting only the type-checker turns zero warnings into an empty criterion).
