# Cross-Target Problem Classification (A–F = Compiler Responsibilities)

This document classifies recurring failures across Boring targets (TypeScript, Kotlin, Rust, Swift, Dart)
into a limited set of **compiler responsibilities**. The purpose of classification is not statistics, but to answer one question:
**Which layer is responsible for a new failure, and therefore where it should be fixed and where it should be verified.**

## Basis of Classification

The classification is derived from existing records of this program, not newly invented:
investigations in `docs/investigations/architecture-round-1/`, two rounds of architecture consultation
(`dc-warn/out/sol-architecture-consult/{SOL2-ARCH-ANSWER.md,ASTRA-ANSWER.md}`),
`CODEX-AUDIT.md`, and the mechanisms of defects already fixed in this session.

## The Six A–F Responsibility Categories

| Category | Responsibility | Input Facts | Owner | Typical Symptom When Boundary Crossed |
|---|---|---|---|---|
| **A** | **Source Fact Extraction** | Types, annotations, literals on the AST | Frontend | Treating unannotated inference as fact |
| **B** | **Representation Selection** | What form the type takes in the target language | Target Backend | Same Haxe type emitted in different forms at different positions |
| **C** | **Boundary Conversion** | Whether wrapping/unwrapping is needed between source and target | Boundary Layer | Missing or duplicate wrapping |
| **D** | **Destination Inference** | What type is needed at this position | **Its enclosing composition** | Borrowing an unrelated return type (**see lambda defect**) |
| **E** | **Effects and Lifetimes** | Evaluation count, laziness, aliasing, lifetime | Composition + Backend | Duplicate evaluation, alias mutation |
| **F** | **Diagnostics and Suppression** | Whether generated code is valid, whether there are warnings | Backend | Warnings treated as acceptable |

## Why Category D Must Have a Clear Owner (The Core Lesson of This Session)

The mechanism of the lambda defect (`dc-warn/out/lambda-return-contract/`) is:
`currentReturnType` is the return type of the **member**; `functionLiteral` does not rebind it,
so all "return site" positions read the type of the **outer function**.

**This is neither a Category B (representation selection) error nor a Category C (missing conversion) error:**
the conversion code itself is correct; what is wrong is **the destination it references**.

⇒ **The owner of Category D is "the composition enclosing that position"**, not the enclosed expression,
nor the outer function. Sol's formulation: *"Composition owns intermediate requirements"*
(`docs/compiler-policy-interfaces.md:169`).

⇒ **Criterion**: if placing the same expression into different compositions yields different (but each correct) output,
then at that position the destination **must** be passed in by the composition and **must not** be inferred from global state.

## Known Instances Across Targets (Mapping, Not Inventory)

| Category | Instance | Record Location |
|---|---|---|
| A | Kotlin: consumer reads inferred facts rather than declared facts | `out/kotlin-local-presence-facts` |
| B | Rust: `String` vs `UString` host string representation | commit `40cf0ad0` |
| B | Swift: `[Int32] = Array(...)` vs `ReadOnlyArray<Int32> = ReadOnlyArray(...)` | commit `9c9548ef` |
| C | Swift: read-only array boundary wrapping (SW04) | `out/sw04-fix-wt` |
| D | Swift: lambda return contract borrows member type | commit `d14aae11` (**with regression, see below**) |
| D | Swift: `switchExpression` derives destination from `sw.t` | `out/switchexpr-destination` (in progress) |
| E | Swift: `switchStatement` strips arm `return` ⇒ control flow error (W1) | commit `d14aae11` |
| F | All: warnings counted toward acceptance (standard `:78`/`:80`) | recorded TCN-156 |

## Rules for Using the Classification

1. **Locate the category first, then the site.** Reporting only "error at some file, some line" does not count as locating.
2. **A fix at one site must not change the behavior of another category.** All four committed fixes underwent full generation-tree comparison;
   byte-for-byte identity is a **necessary condition**.
3. **The owner of a category may differ from the site's location** (Category D is exactly such a case)—
   this is precisely why explicit contracts are needed.
4. **Failure classification must carry attribution**: candidate responsibility / existing repository state / missing documentation
   (lesson recorded from P10, `out/p10-reflection/ACCEPTANCE-REFLECTION.md`).

## What This Classification Does Not Yet Cover

- Failures in **Category J migration** (legacy Kotlin → Haxe) are not classified into A–F;
  CODEX-AUDIT notes "complete J migration were not established".
- Whether **naming consistency** (ReadOnlyArray naming violations) belongs to F or to a separate category is undecided.
- The instance table for each target is **incomplete**: it only lists those recorded in this session,
  not an inventory of all known failures for each target.
