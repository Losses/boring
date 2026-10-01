# Cross-Target Problem Classification (A–F = Compiler Responsibility)

This document groups the failures that recur across Boring's targets (TypeScript, Kotlin, Rust, Swift, Dart)
into a finite set of **compiler responsibilities**. The purpose of the classification is not statistics, but to answer one question:
**which layer should own a new failure, and therefore where it should be fixed and where it should be verified.**

## Basis of the Classification

The classification is drawn from this program's existing records, not newly invented:
the investigations in `docs/investigations/architecture-round-1/`, two architecture consultations
(`dc-warn/out/sol-architecture-consult/{SOL2-ARCH-ANSWER.md,ASTRA-ANSWER.md}`),
`CODEX-AUDIT.md`, and the mechanisms of four defects fixed in this session.

## The Six A–F Responsibility Classes

| Class | Responsibility | Input facts | Owner | Typical symptom when it oversteps |
|---|---|---|---|---|
| **A** | **Source-fact extraction** | types, annotations, literals on the AST | frontend | treating unannotated inference as fact |
| **B** | **Representation selection** | what shape this type takes in the target language | target backend | the same Haxe type emitting different shapes in different positions |
| **C** | **Boundary conversion** | whether wrapping/unwrapping is needed between source and target | boundary layer | missing or duplicated wrapping |
| **D** | **Destination derivation** | what type this position needs | **the composition surrounding it** | borrowing an unrelated return type (**see the lambda defect**) |
| **E** | **Effects and lifetimes** | evaluation count, laziness, aliasing, lifetimes | composition + backend | repeated evaluation, alias mutation |
| **F** | **Diagnostics and suppression** | whether the generated code is legal and warning-free | backend | warnings treated as acceptable |

## Why Class D Must Have an Explicit Owner (This Session's Core Lesson)

The mechanism of the lambda defect (`dc-warn/out/lambda-return-contract/`) is:
`currentReturnType` is the **member's** return type, and `functionLiteral` does not rebind it,
so every "return position" site reads the type of the **outer function**.

**This is not a Class B (representation-selection) error, nor a Class C (missing-conversion) error:**
the conversion code itself is correct; what is wrong is **the destination it refers to**.

⇒ **The owner of Class D is "the composition surrounding the position"**, not the surrounded expression,
and not the outer function either. Sol's phrasing: *"Composition owns intermediate requirements"*
(`docs/compiler-policy-interfaces.md:169`).

⇒ **Criterion**: if placing the same expression into different compositions yields different (but each correct) outputs,
then at that position the destination **must** be passed in by the composition and **must not** be inferred from global state.

## Known Instances by Target (a Mapping, Not a List)

| Class | Instance | Where recorded |
|---|---|---|
| A | Kotlin: consumers read inferred facts instead of declared facts | ~~`out/kotlin-local-presence-facts`~~ worktree no longer exists; **evidence to be supplied** |
| B | Rust: `String` vs `UString` host string representation | commit `40cf0ad0` |
| B | Swift: `[Int32] = Array(...)` vs `ReadOnlyArray<Int32> = ReadOnlyArray(...)` | commit `9c9548ef` |
| C | Swift: read-only array boundary wrapping (SW04) | ~~`out/sw04-fix-wt`~~ worktree no longer exists; **evidence to be supplied** |
| D | Swift: lambda return contract borrows the member type | commit `d14aae11` (**with a regression, see below**) |
| D | Swift: `switchExpression` derives its destination from `sw.t` | ~~`out/switchexpr-destination` (running)~~ worktree no longer exists; **evidence to be supplied** |
| E | Swift: `switchStatement` strips the arm `return` ⇒ control-flow error (W1) | commit `d14aae11` |
| F | All: warnings counted toward acceptance (criteria `:78`/`:80`) | record TCN-156 |

**The two spellings of `out/...` gave opposite results in practice (2026-10-01)**:

| Spelling | Example | Result |
|---|---|---|
| **path inside the worktree** `dc-warn/out/...` | `dc-warn/out/sol-architecture-consult/` | **exists** |
| **bare worktree name** `out/...` | the three spots in the table above | **none exist** |

The two look alike, but in fact one refers to **files in a long-term retained directory** and the other refers to **the temporary worktree itself**.
The former survives because it sits inside `dc-warn`; the latter disappears when the worktree is cleaned up, and leaves no trace.

**The reliability of where things are recorded comes in two kinds (measured 2026-10-01)**:

| Form | Spot-check result |
|---|---|
| commit hashes (`40cf0ad0`, `9c9548ef`, `d14aae11`) | **all three exist** (`git cat-file -t` = commit) |
| `out/...` worktree name (three spots) | **none of the three exist** |

The three `out/` names are `out/kotlin-local-presence-facts`, `out/sw04-fix-wt`, and
`out/switchexpr-destination`; searching under `/home/losses/Development/tq-workspace` by directory name,
branch name, and worktree name all three ways, **none of them exist**. Among them `out/sw04-fix-wt` differs from the actually-existing
`sw04-xcheck-local` by only a few characters, so it is easily mistaken for already verified.

**This is not to say those instances do not exist** — they record facts observed at the time, and the commit hashes remain verifiable.
What fails is **the "where to look"** column: worktrees get cleaned up, and cleanup leaves no trace, so references that point to a worktree
**silently go stale**, and once stale they still read as "verifiable".

**Rule (added later)**: when recording an instance, prefer writing a **commit hash** — commits do not disappear, worktrees do.
If you must reference a worktree, also write down the **observed output or evidence**, so the row remains verifiable after the directory disappears.
Status words like `(running)` are especially dangerous: they assert a **present-tense** fact, and the document will lie as soon as it goes out of sync.

## Rules for Using the Classification

1. **Locate the class first, then the site.** Reporting only "such-and-such file, such-and-such line is wrong" is not locating.
2. **A fix at one place must not change the behavior of another class.** All four committed fixes did a full generated-tree comparison,
   byte-for-byte identical is a **necessary condition**.
3. **A class's owner and where the site lives can differ** (Class D is like this) —
   this is exactly why an explicit contract is needed.
4. **Failure classification must carry an attribution**: candidate's responsibility / existing repository state / missing documentation
   (the lesson recorded by P10, published record `docs/architecture/ACCEPTANCE-REFLECTION.md` §2,
   publish commit `ec4c5c2d`; the earlier draft path `out/p10-reflection/` has been superseded by that publication).

## What This Classification Does Not Yet Cover

- **Class G (tentative name): uniqueness of the criterion source**. A–F divide "**who is responsible for one piece of code**",
  but this item asks "**how many places each independently decide the same thing**". Measured: Rust's `state.shimsUsed`
  has **28 write sites** (3 files) and **12 read sites** (gating emission on it), with **no contract** stating who must write it;
  it is simultaneously treated as "the business referenced some extern" (intent) and as "whether some resident should be written out" (emission),
  and the **two layers are not equivalent** ⇒ modules declared in `runtime/mod.rs` are never emitted (`E0583`).
  This is a **cross-cutting** class: it can appear inside any one of A–F, so it **does not fit** being shoved into A–F;
  recorded as **Contract 6** in `ARCHITECTURAL-CONTRACTS.md`; this section only registers the classification gap.- **Class J migration** (legacy Kotlin → Haxe) failures are not assigned to A–F;
  CODEX-AUDIT points out that "complete J migration were not established".
- **Naming consistency** (the ReadOnlyArray naming violation) — whether it belongs to F or to a separate class is undecided.
- The instance tables by target are **incomplete**: they list only those with records in this session,
  not a list of all known failures per target.

## What This Classification **Deliberately Does Not Cover**: Process/Integrity Classes (See `LAYERED-VERIFICATION.md`)

This file's A–F is a classification of **compiler responsibilities** (who is responsible for one piece of code).
The several things this session repeatedly paid a price for **are not compiler responsibilities**, so they are **not here**,
but in the two sections of `LAYERED-VERIFICATION.md` — to avoid writing the same rule twice:

- **A criterion must state "on which tree it holds"** (the L0 preamble section newly added to that file): the same thing gives
  **opposite conclusions** on the two trees — the hardened guardrail was reviewed and signed off but **was never an ancestor of base**, so base runs the weaker version:
  deleting the real root + the one-word reason `"because"` still **rc=0 PASS**, whereas the hardened version gives rc=1 and names it verbatim.
  It appends a three-step verification method (does the branch exist / is it a base ancestor / **directly read the shared tree** — the third step is the one that actually catches it).
- **Delivery surface: load-bearing pieces must be able to answer "which commit has it"** (same file): tools, guardrails, fixtures, drivers,
  assertion scripts must be checked into the repository; measured `dc-warn/worktrees/` **37/37** all detached and none carrying a commit beyond `e1c65975`,
  and the evidence list mixed in **git-ignored** paths, making "one command rc=0" **hold only for the author's working copy**.
- **"Which tool to use" and "which kind of diagnostics can be seen" must be explained separately** (see the supplement to Contract 3 in `ARCHITECTURAL-CONTRACTS.md`).
  It is **adjacent to but at a different angle from** this file's **Class F** (warnings counted toward acceptance): Class F asks "should it be counted",
  while it asks "can this command **even see** it" (`swiftc -typecheck` reports 0 even in the baseline state ⇒ trusting only the type-checker turns zero warnings into an empty criterion).
