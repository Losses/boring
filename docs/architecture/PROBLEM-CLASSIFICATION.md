# Cross-target problem classification (A–F = compiler responsibilities)

This file maps the recurring failures across Boring's targets (TypeScript, Kotlin, Rust, Swift, Dart)
onto a finite set of **compiler responsibilities**. The purpose of the classification is not bookkeeping, but to answer one question:
**which layer should own a new failure, and therefore where it should be fixed and where it should be verified.**

## Basis of the classification

The classification is drawn from this program's existing records, not newly invented:
the investigations in `docs/investigations/architecture-round-1/`, two architecture consultations
(`dc-warn/out/sol-architecture-consult/{SOL2-ARCH-ANSWER.md,ASTRA-ANSWER.md}`),
`CODEX-AUDIT.md`, and the mechanisms of the four defects already fixed in this session.

## The six responsibility classes A–F

| Class | Responsibility | Input fact | Owner | Typical symptom when it oversteps |
|---|---|---|---|---|
| **A** | **Source-fact extraction** | Types, annotations, literals on the AST | Frontend | Treating an un-annotated inference as a fact |
| **B** | **Representation choice** | What shape this type takes in the target language | Target backend | The same Haxe type emitted in different shapes at different sites |
| **C** | **Boundary conversion** | Whether wrapping/unwrapping is needed between source and target | Boundary layer | Wrapping missing or duplicated |
| **D** | **Destination derivation** | What type this site needs | **The composition surrounding it** | Borrowing an unrelated return type (**see the lambda defect**) |
| **E** | **Effects and lifetime** | Evaluation count, laziness, aliasing, lifetime | Composition + backend | Repeated evaluation, mutation through aliases |
| **F** | **Diagnostics and suppression** | Whether the generated code is legal and has no warnings | Backend | Warnings treated as acceptable |

## Why class D must have an explicit owner (this session's core lesson)

The mechanism of the lambda defect (`dc-warn/out/lambda-return-contract/`) is:
`currentReturnType` is the **member's** return type, and `functionLiteral` does not rebind it,
so every "return-site" site reads the **outer function's** type.

**This is neither a class B (representation choice) error nor a class C (missing conversion) error:**
the conversion code itself is correct; what is wrong is **the destination it refers to**.

⇒ **The owner of class D is "the composition surrounding that site"**, not the enclosed expression,
nor the outer function. Sol's phrasing: *"Composition owns intermediate requirements"*
(`docs/compiler-policy-interfaces.md:169`).

⇒ **Criterion**: if placing the same expression into different compositions yields different (but each correct) outputs,
then at that site the destination **must** be passed in by the composition, and **must not** be inferred from global state.

## Known instances across targets (a mapping, not a list)

| Class | Instance | Recorded at |
|---|---|---|
| A | Kotlin: the consumer reads inferred facts rather than declared facts | `out/kotlin-local-presence-facts` |
| B | Rust: `String` vs `UString` host string representation | commit `40cf0ad0` |
| B | Swift: `[Int32] = Array(...)` vs `ReadOnlyArray<Int32> = ReadOnlyArray(...)` | commit `9c9548ef` |
| C | Swift: read-only array boundary wrapping (SW04) | `out/sw04-fix-wt` |
| D | Swift: lambda return contract borrows the member type | commit `d14aae11` (**with a regression, see below**) |
| D | Swift: `switchExpression` derives the destination from `sw.t` | `out/switchexpr-destination` (in progress) |
| E | Swift: `switchStatement` strips arm `return` ⇒ control-flow error (W1) | commit `d14aae11` |
| F | All: warnings counted into acceptance (standard `:78`/`:80`) | record TCN-156 |

## Rules for using the classification

1. **Locate the class first, then locate the site.** Reporting only "some file some line is wrong" does not count as locating.
2. **A fix in one place must not change the behavior of another class.** All four committed fixes did a full generated-tree comparison;
   byte-for-byte identity is a **necessary condition**.
3. **The class's owner and the site's location can differ** (class D is exactly this) —
   that is precisely why an explicit contract is needed.
4. **A failure classification must carry attribution**: candidate responsibility / existing repository state / missing documentation
   (the lesson recorded by P10, `out/p10-reflection/ACCEPTANCE-REFLECTION.md`).

## What this classification does not yet cover

- **Class G (provisional name): uniqueness of the source of a criterion**. A–F distinguish "**who is responsible for one piece of code**",
  but this item asks "**the same thing being judged separately in several places**". Measured: Rust's `state.shimsUsed`
  has **28 write sites** (3 files) and **12 read sites** (gating emission on them), with **no contract** stating who must write;
  it is simultaneously treated as "the business referenced some extern" (intent) and "whether some resident should be written out" (emission),
  **two layers that are not equivalent** ⇒ the module declared in `runtime/mod.rs` was never written out (`E0583`).
  This is a **cross-aspect** class: it can appear inside any one of A–F, so it is **not suited** to be crammed into A–F;
  it has been recorded as **contract 6** in `ARCHITECTURAL-CONTRACTS.md`, and this section only registers the classification gap.- **Class J migration** (legacy Kotlin → Haxe) failures are not classified under A–F;
  CODEX-AUDIT notes "complete J migration were not established".
- **Naming consistency** (ReadOnlyArray naming violation) — whether it belongs to F or is a separate class is undecided.
- The instance table per target is **incomplete**: it lists only those with records in this session,
  not a list of every known failure per target.

## What this classification **deliberately does not cover**: process/integrity classes (go to `LAYERED-VERIFICATION.md`)

This file's A–F is a classification of **compiler responsibilities** (who is responsible for one piece of code).
The few things this session repeatedly paid a price for are **not compiler responsibilities**, so they are **not here**,
but in two sections of `LAYERED-VERIFICATION.md` — to avoid writing the same rule twice:

- **A criterion must state "on which tree it holds"** (the new L0 prerequisite section in that file): the same thing gives
  **opposite conclusions** on two trees — the hardened guard was reviewed and signed off yet was **never an ancestor of base**,
  so the weak version runs on base: deleting the real root + the one-word reason `"because"` still gives **rc=0 PASS**,
  while the hardened version gives rc=1 and names it verbatim.
  A three-step verification method is attached (does the branch exist / is it an ancestor of base /
  **read the shared tree directly** — the third step is the one that actually catches it).
- **Delivery surface: a load-bearing piece must be able to answer "which commit contains it"** (same file): tools, guards, fixtures,
  drivers, and assertion scripts must be committed; measured `dc-warn/worktrees/` **37/37** all detached and none carrying
  any commit beyond `e1c65975`, and the evidence list mixing in **git-ignored** paths, so that "one command rc=0"
  **holds only for the author's working copy**.
- **"Which tool to use" and "which diagnostics are visible" must be stated separately** (see the supplement to contract 3
  in `ARCHITECTURAL-CONTRACTS.md`). It is **adjacent to but at a different angle from** this file's **class F** (warnings
  counted into acceptance): class F asks "should it be counted", it asks "can this command **see** it"
  (`swiftc -typecheck` reports 0 even in the baseline state ⇒ trusting only the type-checker would turn zero warnings into
  an empty criterion).
