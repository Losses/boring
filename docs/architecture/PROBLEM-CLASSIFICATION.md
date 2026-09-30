# Cross-Target Problem Classification (A–F = Compiler Responsibilities)

This document classifies recurring failures across Boring targets (TypeScript, Kotlin, Rust, Swift, Dart)
into a finite set of **compiler responsibilities**. The purpose is not statistics, but to answer one question:
**Which layer should own a new failure, and therefore where should it be fixed and where should it be verified.**

## Basis of Classification

The classification draws from this project's existing records, not invented anew:
the investigations in `docs/investigations/architecture-round-1/`, two architecture consultations
(`dc-warn/out/sol-architecture-consult/{SOL2-ARCH-ANSWER.md,ASTRA-ANSWER.md}`),
`CODEX-AUDIT.md`, and the mechanisms of four defects already fixed in this session.

## The Six A–F Responsibility Classes

| Class | Responsibility | Input Fact | Owner | Typical Symptom When Overstepped |
|---|---|---|---|---|
| **A** | **Source Fact Extraction** | Types, annotations, literals on the AST | Frontend | Treating un-annotated inference as fact |
| **B** | **Representation Selection** | What form the type takes in the target language | Target Backend | Same Haxe type emitted in different forms at different positions |
| **C** | **Boundary Conversion** | Whether wrapping/unwrapping is needed between source and target | Boundary Layer | Missing or duplicate wrapping |
| **D** | **Destination Derivation** | What type this position requires | **The composition that surrounds it** | Borrowing an unrelated return type (**see lambda defect**) |
| **E** | **Effects & Lifetimes** | Evaluation count, laziness, aliasing, lifetime | Composition + Backend | Repeated evaluation, alias mutation |
| **F** | **Diagnostics & Suppression** | Whether generated code is valid, whether there are warnings | Backend | Warnings treated as acceptable |

## Why Class D Must Have a Clear Owner (The Core Lesson of This Session)

The mechanism of the lambda defect (`dc-warn/out/lambda-return-contract/`) is:
`currentReturnType` is the **member's** return type; `functionLiteral` does not rebind it,
so every "return-site" reads the **outer function's** type.

**This is neither a Class B (representation selection) error nor a Class C (missing conversion):**
the conversion code itself is correct; what is wrong is **the destination it references**.

⇒ **The owner of Class D is "the composition that surrounds the position"**, not the surrounded expression,
nor the outer function. Sol's formulation: *"Composition owns intermediate requirements"*
(`docs/compiler-policy-interfaces.md:169`).

⇒ **Criterion**: if placing the same expression into different compositions yields different (but each correct) output,
then at that position the destination **must** be passed in by the composition and **must not** be inferred from global state.

## Known Instances Across Targets (Mapping, Not Inventory)

| Class | Instance | Record Location |
|---|---|---|
| A | Kotlin: consumer reads inferred facts instead of declared facts | `out/kotlin-local-presence-facts` |
| B | Rust: `String` vs `UString` host string representation | commit `40cf0ad0` |
| B | Swift: `[Int32] = Array(...)` vs `ReadOnlyArray<Int32> = ReadOnlyArray(...)` | commit `9c9548ef` |
| C | Swift: read-only array boundary wrapping (SW04) | `out/sw04-fix-wt` |
| D | Swift: lambda return contract borrows member type | commit `d14aae11` (**with regression, see below**) |
| D | Swift: `switchExpression` derives destination from `sw.t` | `out/switchexpr-destination` (in progress) |
| E | Swift: `switchStatement` strips arm `return` ⇒ control-flow error (W1) | commit `d14aae11` |
| F | All: warnings counted toward acceptance (baseline `:78`/`:80`) | record TCN-156 |

## Rules for Using the Classification

1. **Locate the class first, then the site.** Reporting "wrong line in some file" is not locating.
2. **A fix at one site must not change the behavior of another class.** All four committed fixes ran full output-tree diffs;
   byte-for-byte identity is a **necessary condition**.
3. **The owner of a class can differ from where the site lives** (Class D is exactly this) —
   this is why explicit contracts are needed.
4. **Failure classification must carry attribution**: candidate responsibility / existing repository state / missing documentation
   (lesson recorded from P10, `out/p10-reflection/ACCEPTANCE-REFLECTION.md`).

## What This Classification Does Not Yet Cover

- **Class J migration** (legacy Kotlin → Haxe) failures are not classified into A–F;
  CODEX-AUDIT notes "complete J migration were not established".
- **Naming consistency** (ReadOnlyArray naming violation) — whether it belongs to F or an independent class is undecided.
- The per-target instance table is **incomplete**: it only lists those recorded in this session,
  not an inventory of all known failures across targets.

## What This Classification **Intentionally Excludes**: Process/Integrity Concerns (See `LAYERED-VERIFICATION.md`)

The A–F in this document classify **compiler responsibilities** (who is responsible for a given piece of code).
The things this session repeatedly paid for are **not compiler responsibilities**, hence **not here**,
but in two sections of `LAYERED-VERIFICATION.md` — to avoid writing the same rule twice:

- **Acceptance criteria must state "on which tree it holds"** (the L0 preamble section newly added to that file): the same thing yields
  **opposite conclusions** on two trees — the hardened guardrail was reviewed and signed off yet was **never an ancestor of base**,
  so the weak version runs on base: delete the real root + one-word reason `"because"` still got **rc=0 PASS**,
  while the hardened version gave rc=1 and named it verbatim.
  Includes a three-step verification method (does the branch exist / is it an ancestor of base / **directly read the shared tree** — the third step is the one that catches it).
- **Delivery surface: load-bearing artifacts must answer "which commit contains it"** (same file): tools, guardrails, fixtures, drivers,
  assertion scripts must be checked in; measured `dc-warn/worktrees/` **37/37** all detached with none carrying commits beyond `e1c65975`,
  and the evidence list intermixed **git-ignored** paths, making "one command rc=0" **hold only for the author's working copy**.
- **"Which tool to use" and "what kind of diagnostics it can see" must be explained separately** (see the supplement to Contract 3 in `ARCHITECTURAL-CONTRACTS.md`).
  This is **adjacent to but a different angle from** this document's **Class F** (warnings counted toward acceptance): Class F asks "should it be counted",
  while this asks "can this command **see** it" (`swiftc -typecheck` reports 0 even in baseline state ⇒ relying solely on the type-checker turns zero warnings into a vacuous criterion).
