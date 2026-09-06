# Feature spec 51: Omitted versus explicit null

## Scope

This specification rules the coalescing-default call shape when a caller omits a
trailing argument or passes the explicit `null` literal. It covers TypeScript,
Kotlin, Rust, Swift, and Dart products and the Haxe oracle. The ruling is that
these two source spellings are not distinguishable at the product argument
boundary.

## Current verification

| Evidence | Anchor | Current form |
| --- | --- | --- |
| Default completion | `packages/compiler/DefaultArgExpander.hx:1534` | `omittedCallDefaults(modulePath, fieldName, explicitCount)` completes omitted calls. |
| Default registration | `packages/compiler/DefaultArgExpander.hx:123-147` | Coalescing and optional-without-value registrations use `VNull`. |
| Completion contract | `docs/specs/features/22-default-argument-expansion.md:24-33` | Completion is trailing and a null argument at a registered default position materializes the registered form. |
| Coalescing evaluation | `docs/specs/features/22-default-argument-expansion.md:89-94` | The existing text states the omission-only evaluation rule for coalescing defaults. |

The generation probe reported in `/tmp/dispatch-state/boring-probe-gap47-r1.report.md`,
lines 42-68, observed identical call products for omission and explicit null in
all five targets. The Haxe oracle output is printed at report lines 48-52:
`[Bopomofo:zh-TW,Bopomofo:zh-TW,Bopomofo:fr,Plain:en]` and the three numeric
rows `[4,4,2,0,1]`, `[-4,-4,nan,0,1]`, and `[0,0,0,0,1]`.

## Semantics ruling

1. A call at the product boundary that omits a coalescing-default argument must be rendered
   as the same explicit null value as a source call that supplies `null`.
   TypeScript, Kotlin, Swift, and Dart must therefore render the same `null` or
   `nil` call argument. Rust must render the same `None.clone()` shape when that
   is the target's ownership-preserving null expression. This equality is
   textual at the call boundary; it is not only an equivalence claim.

2. The Haxe oracle must give the same observable result for the omitted and
   explicit-null calls. The lowering layer must not preserve an omission bit or
   introduce an omission-only branch.

3. The degradation layer must not distinguish omission from explicit null.
   Kotlin may emit a native nullable declaration such as
   `locale: String? = null`, but that declaration must not be used as an
   omission-specific observation: the call products remain explicit `null` in
   both cases.

4. The coalescing default value is evaluated in the function body on every
   invocation, including invocations reached through an explicit-null argument
   and invocations with a non-null explicit argument. The implementation must
   not claim an observable distinction between this behavior and evaluating
   only on omission. This ruling records the required product behavior for this
   shape and supersedes the omission-only evaluation wording in feature spec
   22, rules 2 and 3, for the coalescing default covered here.

5. The body-side coalescing operation must retain the ordinary target form:
   TypeScript `locale ?? selected`, Kotlin `locale ?: selected`, Rust's
   `None => selected` matching form, Swift `locale ?? selected`, and Dart
   `locale ?? selected`, as observed in the probe report at lines 63-68.

## Contract examples

| Haxe source call pair | Required product relationship | Haxe oracle relationship |
| --- | --- | --- |
| `describe(Bopomofo)` and `describe(Bopomofo, null)` | Calls are textually identical after completion: `null` or `nil`; Rust uses the same `None.clone()`. | Same result for both calls. |
| `describe(Plain)` and `describe(Plain, null)` | Calls are textually identical after completion. | Same result for both calls. |
| `describe(Bopomofo, "fr")` | The non-null explicit value remains explicit and is not replaced by the default. | The explicit locale result remains distinct from the null pair. |

The concrete five-target call spellings and the oracle rows are evidence from
`/tmp/dispatch-state/boring-probe-gap47-r1.report.md:48-68`.

## Non-goals

This specification does not introduce a new default-argument mechanism, change
constant-default completion, or define a target-specific omission marker.
