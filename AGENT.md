# AGENT.md

boring is a Haxe package that exposes the transpilation toolchain to
tiqian. tiqian provides the original Haxe sources and translates them to
each platform through the reflaxe targets under `packages/compiler/reflaxe/`. This
repository hosts the targets, the interception pass, the capability
samples under `samples/`, the generation entries under `examples/`, the
hand-written reference translations under `reference/`, and the tooling
that checks repository rules.

## License and working language

Every package in this repository is MIT licensed. The working language is
English. Code, identifiers, comments, commit messages, and documents are
written in English.

## Language style constraints

Text in this repository follows the style rules below. The automated check
is `bun tools/doc-style/check.ts`; it scans Markdown documents and comments in
supported Haxe, TypeScript, Rust, Kotlin, Swift, Dart, Nix, shell, HXML, and
TOML files. Generated trees, build output, dependencies, and imported Unicode
data are excluded.

1. Use plain professional vocabulary. Name actions with direct verbs.
2. No metaphors and no figurative verbs used as technical terms. The banned
   word list with its category comments lives in `tools/doc-style/check.ts`.
3. No internet jargon and no business-speak vocabulary.
4. No negate-first contrast constructions and no em-dashes.
5. No filler transitions that restate the previous sentence.
6. No putdown wording and no decorative adjectives.
7. The word list grows with each correction: when a review fixes a wording
   problem, add the new word or pattern to the checker in the same change.
8. Every hit from the checker is a candidate for manual judgment. Judge
   each hit, rewrite the ones that violate the rules, and keep fixed
   phrases that are correct in context.
9. The allowlist in the checker is locked. Expanding it requires explicit
   permission from the repository owner.
10. The checker is an automated checklist. It does not replace reading the
    final text before submitting.

## Strong typing rules

TypeScript in this repository is strict, and the ESLint plugin in
`tools/eslint` enforces the typing rules:

- `any` is banned in every position (`no-explicit-any`,
  `no-unsafe-function-type`, `no-empty-object-type`).
- Chained type assertions are banned: `as unknown as T`, `as A as B`, and
  the angle-bracket form (`boring/no-double-assertion`).
- Inline object types, function types, mapped types, and tuple types are
  banned outside the direct right-hand side of a type alias
  (`boring/no-inline-types`). Bind the type to a name and reference the
  name at the use site.
- Interfaces declare data shape only. Method signatures in interfaces are
  banned (`boring/no-interface-methods`). Declare a property whose type is
  a named function type alias.
- Inline ESLint directives are banned with no exceptions
  (`boring/no-eslint-disable`, together with `linterOptions.noInlineConfig`):
  no `eslint-disable` comment of any form and no inline rule override. A
  rule violation is fixed in the code, or the rule is changed in
  `eslint.config.ts` for every file at once. Silencing a rule for one file
  is never an option.

Rust follows the same discipline: zero `as` casts, errors returned as
`Result` values, and conversions checked before they run. Haxe code avoids
`Dynamic`; platform APIs are declared as typed externs and errors are
reported as `haxe.Exception` values.

## Build and test

All commands run inside the flake environment:

    nix develop -c bash -c "bun install"
    nix develop -c bash -c "bun run verify"

`bun run verify` runs every check in order: the three generation passes
(`gen:ts`, `gen:kotlin`, `gen:rust` through the example entries),
`bun test`, the Haxe test binary, the Kotlin test binary, the
interception suite, the Rust test suite, `eslint .`, `tsc -p .`, the
documentation style check, the vector regeneration check, and the
reflaxe smoke compile. Individual commands:

| Command | Effect |
| --- | --- |
| `bun test` | TypeScript tests under bun |
| `bun run test:haxe` | Compile Haxe and run its checks |
| `bun run test:kotlin` | Compile Kotlin and run its checks |
| `bun run test:rust` | Cargo tests for the Rust codec |
| `bun run lint` | ESLint with the repository rules |
| `bun run typecheck` | `tsc -p .` with no emit |
| `bun run check:docs` | Documentation style check |
| `bun run gen:vector` | Regenerate `tests/vectors/roundtrip.bin` |
| `bun run check:reflaxe` | Compile a smoke file against the pinned reflaxe |
| `bun run commit` | Commit through the repository commit tool |
| `bun run install:hooks` | Install the git hooks from `tools/git-hooks/` |

## Layout

- `packages/compiler/`: the transpilation toolchain, exposed as the `boring` haxelib
  package through `haxelib.json` (class path, reflaxe dependency),
  `extraParams.hxml` (the documented set of package parameters), and
  `defines.json` (the define descriptions registered for
  `haxe --help-defines`). It holds the interception pass
  (`packages/compiler/Intercept.hx`), the shared runtime-package configuration
  (`packages/compiler/RuntimeConfig.hx`), and the reflaxe targets under
  `packages/compiler/reflaxe/ts/`, `packages/compiler/reflaxe/kotlin/`, and `packages/compiler/reflaxe/rust/`,
  each with its compiler package and its `std-shadow` of the `haxe.io`
  externs. The target directories sit at non-package-aligned depth, so
  a compilation adds them through explicit class paths as the examples
  do.
- `samples/`: the Haxe capability samples; every file under `samples/`
  demonstrates language capabilities of the translatable subset, and the
  sample set grows as the accepted construct set grows. The subset's own
  standard library lives under `samples/std/`; the `haxe.*` and `std`
  namespaces are compile-input identities only and never reach target
  output (docs/specs/stdlib/06-std-modules.md).
- `examples/`: the generation entries (`ts.hxml`, `kotlin.hxml`,
  `rust.hxml`) and the reflaxe smoke file (`Smoke.hx`). Each generation
  entry demonstrates package consumption: `-lib boring` for the package
  class path, the per-target class paths, the interception macro, the
  target activation macro, and the output and runtime defines. The
  entries carry no implementation.
- `reference/ts/`: the hand-written TypeScript reference translation,
  published as the `@boring/codec` package, a member of the bun
  workspace at the root `package.json`. `reference/ts/gen/` is the
  gitignored tree generated by the reflaxe TypeScript target; `verify`
  regenerates it first and the behavior and structure guards run
  against that output.
- `reference/rust/`: the hand-written Rust reference translation, a
  member of the cargo workspace at the root `Cargo.toml`.
  `reference/rust-gen/` is the generated Rust crate of the same
  workspace; its sources are gitignored and regenerated by `verify`.
- `reference/kotlin/`: the hand-written Kotlin reference translation,
  compiled by `kotlinc` directly with no build tool.
  `reference/kotlin/gen/` is the gitignored tree generated by the
  reflaxe Kotlin target; `verify` regenerates it first and
  `test:kotlin` runs its checks against that output.
- `tests/`: every test suite and the shared evidence:
  `tests/ts/` (bun tests), `tests/haxe/` (test runner plus
  `compile.hxml`), `tests/kotlin/` (test runner compiled with the
  sources), `tests/rust/` (cargo test targets, wired into
  `reference/rust/Cargo.toml` and `reference/rust-gen/Cargo.toml`
  through explicit `[[test]]` paths; a suite carries
  no manifest of its own), and `tests/vectors/` (the shared vectors).
- `tools/`: the ESLint plugin, the documentation style checker, the
  commit tool, the git hooks, and the vector generator.

Test tooling and language implementations are separate trees: a language
implementation lives under `packages/compiler/`, `samples/`, or `reference/`;
everything that verifies an implementation lives under `tests/`. No
language keeps a separate runtime tree: TypeScript runs under bun, Rust
builds with cargo, the Haxe test binary is compiled JS executed by bun,
and the Kotlin test binary is a jar executed on the JVM. Build outputs
go under the gitignored `out/`.

## Test vectors

`tests/vectors/roundtrip.bin` is fixed evidence, and the tests treat it
as read-only input. `roundtrip.json` is the editable description;
`bun run gen:vector` rewrites the binary from it and runs only when the
record format changes. The TypeScript, Haxe, Kotlin, and Rust tests
decode the same committed bytes and encode the same records back.

Any change to the record format updates the generator, all four
implementations, and the vectors in one change. A byte disagreement
between languages is a test failure in every language.

## Data comparison policy

No implementation writes its own JSON serializer or parser. JSON is the
repository convention for describing test data; comparing outputs happens
through the AST (the Haxe implementation is the reference) or through
direct comparison of the binary sequences. The binary format with its
written spec localizes a disagreement: the first differing field
identifies the encoder stage that failed. This boundary is a prerequisite
for unit tests that stay useful across four languages.

## Commits

Commit messages follow Conventional Commits 1.0.0, in English. The only
permitted way to create a commit is the repository tool:

    bun tools/commit/commit.ts "feat(codec): add bounds encoding"

The tool validates the header, the body, and the footer region against the
standard, rejects every `Co-Authored-By` trailer and every other trailer
that credits an author, and prints the correct form together with the
violations when a message fails. Committing through plain `git commit` is
not part of the workflow.

Autonomous commits are authorized for this repository: an agent working
here commits its finished work in the conventional format without asking
first. Commits never carry a `Co-Authored-By` trailer and never credit
anything besides the change itself.

Run `bun tools/git-hooks/install.ts` once per clone. The hooks run the
documentation style check before a commit and the message check before
the message is stored; a failed check blocks the commit.
