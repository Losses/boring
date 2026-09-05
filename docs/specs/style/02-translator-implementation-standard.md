# Style spec 02: Translator implementation standard

## Scope

This specification rules the implementation of the translators themselves: where a translation mechanism lives in the compiler source, how a mechanism repeated across the target printers is consolidated into the shared compiler layer, which shapes a per-target exception may take, what quality the emitted code must meet, and where a translation defect is fixed. Style spec 01 rules the Haxe source accepted as input; this document rules the compiler that consumes it.

The five targets are Kotlin, Rust, Dart, TypeScript, and Swift. The shared compiler layer is the flat module set under `packages/compiler/`. Each target printer lives under `packages/compiler/reflaxe/<target>/<target>compiler/`.

## Layer ownership

Compiler source divides into two kinds of code by what it produces.

1. **Decision code** computes an answer from the typed AST: a classification, a query, an analysis, or a whole-tree rewrite. When two or more targets need the same answer, the decision code lives in the shared layer as one flat module directly under `packages/compiler/`, named after the mechanism, guarded with `#if (macro || reflaxe_runtime)`. Existing modules follow this rule: `DefaultArgExpander.hx` and `PipelineExpander.hx` (whole-tree rewrites), `StaticReferenceScan.hx` (fixed-point scan of private static references), `TerminationAnalysis.hx` (control-flow exit analysis), `StructuralKeyValidator.hx` and `PolicyQueries.hx` (field key queries).
2. **Rendering code** produces target text: a declaration, statement, expression, or literal in the target's syntax. Rendering code lives in the target printer. Two targets rendering the same Haxe construct with different text is the normal state of the printers and carries no duplication finding.

Two rules follow:

3. A shared module never emits target text and never branches on the target name. A mechanism that needs per-target variation takes one of the exception shapes in the next section.
4. Adding a new copy of an existing shared mechanism inside a target printer fails review. The target consumes the shared module.

## Consolidation procedure

A mechanism that exists as parallel copies in several target printers (the same function name, or the same decision reached by equivalent code) is consolidated into the shared layer in a fixed order. Nothing is edited before every copy has been compared.

**Step 0, classify every difference.** The copies are compared line by line and each difference receives one of three verdicts:

- **Verdict (i), target syntax.** The difference is output text that necessarily uses the target's syntax. The rendering stays in the target printer; the shared decision logic is consolidated without it.
- **Verdict (ii), equal output.** The code texts differ while the observable output is the same. Equality is demonstrated before consolidation: the consolidating commit must leave every generated tree byte-identical, and where the difference could change a runtime value, a probe fixture exercises the path on every target first.
- **Verdict (iii), behavioral divergence.** The copies produce different observable behavior. Work stops. Both behaviors, their outputs, and a minimal Haxe trigger go to the repository owner, and the owner picks the behavior. Consolidating one side without a ruling is banned.

**Step 1, consolidate.** The majority body moves into a new or existing shared module. Each copy becomes a delegation that keeps its declared signature (static or instance, per the target's existing call shape), so call sites in the target printer do not change.

**Step 2, verify.** All eight generation trees regenerate. Every target the change does not touch must remain byte-identical: the manifest diff is empty. The touched targets keep their suites green. `bun run test:consistency` passes with fresh producer runs. `bun run check:docs` and the Haxe formatter pass on the touched compiler files.

The field key policy consolidation is the reference example. `PolicyQueries.hx` holds `canEmitDataClassComparator`, `isDataClassFieldKey`, `isStructKeyCandidate`, and `isFieldKeyCandidate`; the five `*Type.hx` and `*Decl.hx` copies delegate to it. Its Step 0 comparison classified the Kotlin switch arm order as verdict (ii) (disjoint constructors, equal output) and the Dart `static` qualifier as verdict (i) (invocation shape, same boolean returned). No verdict (iii) row existed, so no owner ruling was required.

## Exception shapes

A shared mechanism with per-target variation uses one of five shapes. A variation outside these five shapes needs an owner ruling before implementation.

1. **Profile data.** The variation is finite declarative data. The shared mechanism receives it as a data value and contains no target branch. New work of this shape registers in the exception ledger from its first commit.
2. **Narrow callback.** The variation is one named decision. The shared mechanism calls a target-supplied function for that decision alone. `StaticReferenceScan.scan(mtypes, inEmissionScope, alwaysKeepClass)` receives its scope and always-keep decisions this way.
3. **Internal diagnostic branch.** A branch inside a shared module may key on the target for a diagnostic message. Carrying a semantic decision this way permanently is banned: the branch either disappears when the diagnostic work ends or moves to another shape.
4. **Default with named override.** The shared module defines one named step of its algorithm with a default implementation, and a target replaces that step by name. The override replaces the step; it may not re-run or skip surrounding steps.
5. **Separate mechanisms.** When Step 0 returns verdict (iii) and the owner keeps both behaviors, the targets keep two independent mechanisms with their own names. Presenting them as one shared mechanism with a hidden branch is banned.

**Exception ledger (ruled; implementation pending).** Every standing exception registers at compile time in a `SemanticException` registry with an identifier, the mechanism, the target, the reason, and the fixture that verifies it. The registration contract rejects missing, duplicate, and unknown identifiers. The continuous-integration artifact `out/semantic-pass-exceptions.json` carries the exception count and its delta against a baseline; an increase requires a new fixture and an owner ruling. A count that keeps growing is the signal that the abstraction boundary sits in the wrong place.

## Emission quality

1. Generated code compiles without warnings on every target: kotlinc, rustc, the TypeScript compiler, the Dart analyzer, and the Swift type-checker. A translation that produces a warning is an emitter defect with the same severity as a translation that produces wrong output.
2. Warning suppression markers are banned in generated trees: no `@Suppress` or `@SuppressWarnings` (Kotlin), no `#[allow]` (Rust), no `@ts-ignore`, `@ts-expect-error`, or `eslint-disable` marker (TypeScript), no `// ignore:` comment (Dart). The emitter produces code that does not warn.
3. Acceptance for any emitter change counts the warning lines in the target suite output that name files under the generated trees; the count is zero. A change that replaces a warning with a suppression marker fails acceptance.
4. Cross-target behavior is held by `bun run test:consistency`: it runs the shared test set on all six runners (haxe, TypeScript, Kotlin, Rust, Swift, Dart) over fresh producer output and requires equal results. Consistency verifies the covered tests; divergences outside the covered tests are found by the Step 0 comparison of the consolidation procedure, which is why Step 0 reads every copy before any editing.

## Fix location

1. A defect in translated output is fixed in the translator: the target printer (`packages/compiler/reflaxe/<target>/**`) for rendering defects, the shared layer (`packages/compiler/`) for mechanism defects.
2. Editing `samples/` or `tests/` Haxe source to make a translation defect disappear is banned. The single exception is a Haxe semantic the target language cannot carry; in that case the change record names the semantic and states why the common layer cannot express it.
3. Generated trees are gitignored build artifacts. They are regenerated, hashed, and compared during acceptance; they are never committed and never edited by hand to satisfy a check.
