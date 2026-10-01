# Architecture consultation request: Boring compiler (Haxe -> 5 targets)

You are being consulted as an ARCHITECT, not as a worker. Do not write code. The
requester has spent ~50 agent-rounds on this programme and is stuck at the
ARCHITECTURE level while being productive at the DETAIL level. We want your
judgment on what the actual problem is and what the next architectural move
should be.

## The repository and its own architecture document

Repo: Boring, a Haxe -> multi-target compiler (targets: haxe/JS, TypeScript,
Kotlin, Dart, Rust, Swift, each also in an f32 precision variant = 10 targets).
Pinned revision `e1c65975`. A coordination worktree sits at
`boring-wt-architecture/`.

The repo ALREADY CONTAINS an architecture document that defines the problem
space. Read it first; it is authoritative and I want your judgment anchored in
it, not in my summary:

- `docs/compiler-policy-architecture.md` lines ~98-103: defines six compiler
  RESPONSIBILITIES, labelled A-F:
  - A: Value and declaration representation (stable declaration/body storage,
    produced values, destination requirements, conversions, defaults)
  - B: Flow and evaluation (binding identity, invalidation, branch/loop/exception
    joins, operand effects, evaluation order)
  - C: Identity and writable places (alias visibility, object sharing, container
    lifetime, original assignment location through projections)
  - D: Control-flow results (branch values, return/assignment/discard intent,
    reachable exits, structured joins)
  - E: Intrinsics and platform integration (numeric/string domains, helper
    signatures, replacement-call results, imports, module closure)
  - F: Evidence and diagnostics (occurrence lineage, policy decision records,
    source mapping, child output retention, layered conformance)
  The document states A, B, C, E, F may proceed concurrently on interface design
  and inventory; D's implementation follows agreed A and B interfaces.

- `docs/investigations/architecture-round-1.md` section at line 232,
  "Responsibility map and implementation dependencies": a six-row table mapping
  MECHANISMS (numeric conversions; string operations; null flow; evaluation;
  identity and sharing; output structure) to (a) "facts that must have a defined
  producer", (b) target responsibility, (c) next useful evidence. It also gives
  an ordered work order 1-4:
    1. Establish explicit boundary decisions and source/target distinctions;
       Swift array conversion is the first investigation; resolve any semantic
       decision required before implementing.
    2. Prepare numeric conversion and operand-evaluation specifications
       independently.
    3. Apply established evaluation facts to string operations and null proofs.
    4. Carry branch result and exit intent into target structure.
  The same document explicitly says: "This remains a sampled architecture survey,
  with runtime behavior and uninspected forms explicitly unresolved" and "It has
  not accepted an implementation, a new semantic ruling, or a full runtime
  coverage claim."

- `docs/architecture-work-plan.md` defines programme gates P00-P12. P00-P07 and
  P11 are marked done; **P08, P09, P10, P12 are open**. Line 134 says:
  "P08-P10 and P12 remain open pending accepted fixed-input regression evidence."
  P08 = "Delegate reproduction and behavior tests, then implementation.
  Independently review both before accepting a candidate."
  P09 = "Run the candidate's required Boring checks AND Tiqian checks on fixed
  inputs." (Tiqian is a downstream consumer repo, pinned separately.)

## What has actually been done (~50 rounds), and my diagnosis

The work has been almost entirely at the VERIFICATION/DETAIL layer:
- A fixed-input regression run over 10 targets that reaches
  "All 10 targets ... are 100% consistent across 736 tests" (a cross-target
  consistency check over test ids).
- Full attribution of a 48-failure Stage 4 suite: 4-bucket classification
  (48 pre-existing at base / 0 introduced by our changes / 0 from others'
  in-flight edits / 0 unclassified), with per-failure assertion fingerprints
  identical 48/48 across two trees.
- Fixes to individual symptoms: a Swift double-wrap codegen bug; a Rust
  module-keyed state-map collision (one axis of it); a family of stale test
  expectations about the Rust string type (`UString` vs host `String`);
  test timeout budgets; a roots-guard script hardening; a log-seal
  byte-offset checker.
- Many findings recorded as PIT/TCN notes (traps and cross-task judgements).

**My own diagnosis of why P08-P12 are stuck** (challenge this):
1. I have been treating "evidence is complete" as "architecture has advanced".
   The verification artefacts are dense and self-consistent, but they all answer
   "are the generated outputs mutually consistent?" - NOT "which mechanism is
   owned by whom, and which producer is missing?".
2. Concretely: of the six mechanisms in the responsibility map, I have not
   established a defined PRODUCER for any one. I have never worked the ordered
   work order step 1 (boundary decisions / Swift array conversion) as a
   decision - only its downstream symptom (a double-wrap fix).
3. The `driver-verify` "100% consistent across 736 tests" result proves output
   agreement between targets; it does NOT prove the mechanisms are correct. The
   repo's own document says an implementation and a full runtime coverage claim
   have NOT been accepted.
4. Two consecutive falsifications showed my "fixes" closed only one AXIS of a
   defect class each time:
   - A module-keyed map fix closed the class-identity axis, but a second axis
     (two payload enums in ONE module) still emits an unresolved import
     (`E0432`) at the fixed state.
   - A stale-expectation fix touched 9 test files / cleared 6 failures, but an
     independent scope measurement found the real family is 48 stale lines
     across 14 files (plus 3 more of a *different* family in Swift, container
     model drift, not a string-type analogue).
5. A newly found trap that undermines verification itself:
   `tests/ts/package-artifacts.test.ts` writes a stub INTO A TRACKED SOURCE FILE
   (`samples/boring/MathNaNTestSupport.hx`) and restores it WITHOUT `try/finally`.
   When a test is killed by a timeout the stub is left permanently, so any
   execution root that has run the suite repeatedly is silently degraded, and
   any "same tree, two runs" comparison built on it is compromised.

## What I want from you

Please answer as an architect, and be direct about where my framing is wrong:

1. **Is my diagnosis correct** - i.e. is the real blocker that no mechanism has a
   defined producer, and that consistency evidence is being substituted for
   architectural decisions? If not, what IS the real blocker?
2. **Given the repo's own responsibility map and work order, what is the single
   next architectural move?** Be specific about what artefact should exist at the
   end of it, and how we would know it is done - not a task list, a decision.
3. **Is the ordered work order 1-4 still the right order**, given that five
   "candidate repairs" were attempted before step 1 completed? If the order
   should change, say so and why.
4. **What should P08's "independently review both before accepting a candidate"
   actually MEAN** in architectural terms, so that it cannot be satisfied by
   density of evidence? Propose a concrete acceptance condition.
5. **What is the minimum fixed-input evidence set that could justify P09 passing**,
   given that P09 requires BOTH Boring checks and Tiqian checks? If Tiqian is not
   even available locally, is P09 simply blocked, or is there a legitimate way to
   make progress on it?
6. **Name the risk I am most likely blind to**, given the pattern above
   (verification-dense, decision-poor; fixes that close one axis at a time).

## Constraints you should respect in your answer
- Do not propose writing code. This is a decision/judgment request.
- Do not simply endorse my framing; if it is self-serving or wrong, say so.
- Assume the repo's own documents are more authoritative than my summary, and
  say where my summary arguably misreads them.
- Where you need a fact that is not in this brief, say exactly what you would
  look at, rather than assuming.
