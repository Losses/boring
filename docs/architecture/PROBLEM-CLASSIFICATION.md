# Cross-Target Problem Classification (A–F = Compiler Responsibilities)

This document maps recurring failures across Boring targets (TypeScript, Kotlin, Rust, Swift, Dart)
into a finite set of **compiler responsibilities**. The purpose of this classification is not statistics, but to answer one question:
**Which layer should own a new failure, hence where should it be fixed, and where should it be verified.**

## Basis of Classification

The classification is drawn from existing records of this project, not invented:
investigations in `docs/investigations/architecture-round-1/`, two rounds of architecture consultation
(`dc-warn/out/sol-architecture-consult/{SOL2-ARCH-ANSWER.md,ASTRA-ANSWER.md}`),
`CODEX-AUDIT.md`, and the mechanisms of four defects already fixed in this session.

## The Six A–F Responsibility Classes

| Class | Responsibility | Input Fact | Owner | Typical Symptom When Crossed |
|---|---|---|---|---|
| **A** | **Source Fact Extraction** | Types, annotations, literals on the AST | Frontend | Treating unannotated inference as fact |
| **B** | **Representation Selection** | What form this type takes in the target language | Target backend | Same Haxe type emitted in different forms at different sites |
| **C** | **Boundary Conversion** | Whether wrapping/unwrapping is needed between source and target | Boundary layer | Missing or duplicate wrapping |
| **D** | **Destination Inference** | What type this position needs | **The composition surrounding it** | Borrowing an unrelated return type (**see lambda defect**) |
| **E** | **Effects and Lifetimes** | Evaluation count, laziness, aliasing, lifetimes | Composition + backend | Duplicate evaluation, alias mutation |
| **F** | **Diagnostics and Suppression** | Whether generated code is legal, has warnings | Backend | Warnings treated as acceptable |

## Why Class D Must Have an Explicit Owner (the Core Lesson of This Session)

The mechanism of the lambda defect (`dc-warn/out/lambda-return-contract/`) is:
`currentReturnType` is the return type of the **member**, `functionLiteral` does not rebind it,
so every "return site" reads the type of the **outer function**.

**This is not a Class B (representation selection) error, nor a Class C (missing conversion):**
the conversion code itself is correct; what is wrong is **the destination it references**.

⇒ **The owner of Class D is "the composition surrounding that position"**, not the enclosed expression,
nor the outer function. Sol's formulation: *"Composition owns intermediate requirements"*
(`docs/compiler-policy-interfaces.md:169`).

⇒ **Criterion**: if placing the same expression in different compositions yields different (but each correct) output,
then at that position the destination **must** be passed in by the composition, and **must not** be inferred from global state.

## Known Instances Across Targets (Mapping, Not a List)

| Class | Instance | Record Location |
|---|---|---|
| A | Kotlin: consumer reads inferred facts instead of declared facts | `out/kotlin-local-presence-facts` |
| B | Rust: `String` vs `UString` host string representation | commit `40cf0ad0` |
| B | Swift: `[Int32] = Array(...)` vs `ReadOnlyArray<Int32> = ReadOnlyArray(...)` | commit `9c9548ef` |
| C | Swift: read-only array boundary wrapping (SW04) | `out/sw04-fix-wt` |
| D | Swift: lambda return contract borrows member type | commit `d14aae11` (**with regression, see below**)|
| D | Swift: `switchExpression` derives destination from `sw.t` | `out/switchexpr-destination` (in progress)|
| E | Swift: `switchStatement` strips arm `return` ⇒ control-flow error (W1) | commit `d14aae11` |
| F | All: warnings counted toward acceptance (standard `:78`/`:80`) | Recorded TCN-156 |

## Rules for Using the Classification

1. **Locate to class, then locate to site.** Reporting only "wrong at file X line Y" is not locating.
2. **A fix at one place must not change behavior of another class.** All four committed fixes performed full generated-tree diffs;
   byte-for-byte identical is a **necessary condition**.
3. **A class's owner and the site's location can differ** (Class D is one such case) —
   that is precisely why explicit contracts are needed.
4. **Failure classification must carry attribution**: candidate responsibility / existing repo state / missing documentation
   (lesson recorded in P10, published record `docs/architecture/ACCEPTANCE-REFLECTION.md` §2,
   publication commit `ec4c5c2d`; the earlier draft path `out/p10-reflection/` has been superseded by that publication).

## Not Yet Covered by This Classification

- **Class J migration** (legacy Kotlin → Haxe) failures are not classified into A–F;
  CODEX-AUDIT notes "complete J migration were not established".
- **Naming consistency** (ReadOnlyArray naming violation) whether it belongs to F or a separate class is undecided.
- The instance table per target is **incomplete**: it only lists those recorded in this session,
  not the full inventory of known failures per target.

## What This Classification **Intentionally Does Not Cover**: Process/Integrity Concerns (See `LAYERED-VERIFICATION.md`)

The A–F in this document is a classification of **compiler responsibilities** (who is responsible for a piece of code).
The things this session has repeatedly paid the price for are **not compiler responsibilities**, hence **not here**,
but in two sections of `LAYERED-VERIFICATION.md` — to avoid writing the same rule in two places:

- **Criteria must state "on which tree they hold"** (the new L0 prerequisite section added to that file): the same thing gives
  **opposite conclusions** on two trees — the hardened guardrail was reviewed and signed off yet **was never an ancestor of base**, so the weak version runs on base:
  deleting the true root + the one-word rationale `"because"` still yields **rc=0 PASS**, while the hardened version yields rc=1 and names it verbatim.
  With a three-step verification method (whether the branch exists / whether it is an ancestor of base / **directly read the shared tree** — the third step is the one that catches it).
- **Delivery surface: load-bearing artifacts must be able to answer "which commit contains it"** (same file): tools, guardrails, fixtures, drivers,
  assertion scripts must be committed; measured `dc-warn/worktrees/` **37/37** all detached and none carrying a commit beyond `e1c65975`,
  and the evidence list mixed in **git-ignored** paths, making "one command rc=0" **only true for the author's working copy**.
- **"Which tool to use" and "which diagnostics it can see" must be explained separately** (see `ARCHITECTURAL-CONTRACTS.md` Contract 3 supplement).
  This is **adjacent to but at a different angle from** this document's **Class F** (warnings counted toward acceptance): Class F asks "should it be counted",
  while this asks "can this command **see** it" (`swiftc -typecheck` reports 0 even in baseline state ⇒ trusting only the type-checker makes zero warnings an empty criterion).
