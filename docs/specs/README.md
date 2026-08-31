# Translation specifications

This directory defines the translation rules from Haxe into Rust, TypeScript, and Kotlin for the boring repository.

## Purpose

The repository hosts one binary codec implemented in Haxe, Rust, TypeScript, and Kotlin. Haxe is the reference language. Every Haxe construct used by the codec requires an explicit, written translation rule for Rust, TypeScript, and Kotlin.

The Kotlin tree is present under `reference/kotlin/`. The Kotlin rulings in these specifications bind the Reflaxe generator when it emits a Kotlin target, so the target arrives with its translation decisions already written down.

A later compilation and generation stage produces or verifies target code against these specifications. Without written specifications, unit tests inherit ad hoc translation choices, and disagreements in emitted bytes cannot be localized to a single design decision. Each specification document serves as the single location where a translation decision is defined and justified.

## Classification

Specifications are organized into six categories:

1. `binary/`: Rules governing the binary record family: byte layout, code generation from annotated record typedefs, reading, compiler optimization, and the consumer boundary. Each file rules one mechanism across the entire family.
2. `features/`: Rules governing Haxe language constructs. Each file defines the syntax, semantics, typed-AST representation, and cross-language mappings for one construct.
3. `macros/`: Rules governing boring's built-in compile-time rewrites: constructs that are not Haxe language features and expand in the common layer before target emission. Collection pipeline idioms and the record copy live here, never in `features/`.
4. `stdlib/`: Rules governing Haxe standard library modules and functions. These documents define standard library substitutions for the target languages.
5. `style/`: Rules governing the Haxe source standard itself and the interception that enforces it before generation.
6. `targets/`: Rules governing one additional target language across the whole construct list. Each document holds every ruling for its target, cross-referencing the per-construct specifications for the Haxe-side semantics, and binds that target's Reflaxe generator.

## Judgment axes

Every candidate translation is evaluated across four fixed axes:

- `performance`: Runtime cost on the codec hot path, including allocation counts, bounds checks, pointer indirection, and compiler optimization characteristics. Evaluations cite concrete mechanisms.
- `ambiguity`: Likelihood of misinterpretation by a human reader or compiler. Evaluations address implicit conversions, unspecified bit widths, and target-specific behaviors.
- `redundancy`: Extent of duplicate state or duplicated logic forced across the language implementations.
- `readability`: Directness with which the target code expresses its intent to an engineer proficient in that language.

## Specification index

### Binary specifications

| Number | Specification | Status | Description |
| --- | --- | --- | --- |
| 01 | [01-binary-record-layout.md](binary/01-binary-record-layout.md) | Complete | Byte layout, endianness, field packing, count domain, and dyadic test-value precision. |
| 02 | [02-binary-record-io.md](binary/02-binary-record-io.md) | Planned | The `@:binaryRecord` annotation and the code the compiler derives from it: offsets, buffer kinds, position types, read functions, encode, decode, and the record copy. |
| 03 | [03-diff-localization.md](binary/03-diff-localization.md) | Complete | Offset calculation and mapping byte diffs to encoder functions. |
| 04 | [04-key-index-retrieval.md](binary/04-key-index-retrieval.md) | Complete | Generated per-key accessors reading fields at build-time offsets. |
| 05 | [05-block-float-widths.md](binary/05-block-float-widths.md) | Complete | Block float width marker, binary32 and binary16 fields, and edge rounding. |
| 06 | [06-binary-record-views.md](binary/06-binary-record-views.md) | Planned | Reading records by position: one buffer read per field, iteration as position arithmetic, no per-record allocation. |
| 07 | [07-binary-record-optimization.md](binary/07-binary-record-optimization.md) | Planned | The compiler rewrite threading one implicit record buffer parameter per buffer kind through position-reading functions. |
| 08 | [08-binary-record-boundary.md](binary/08-binary-record-boundary.md) | Planned | The published-versus-internal declaration split, materialization at returns, and cross-library declaration files. |

### Language feature specifications

| Number | Specification | Status | Description |
| --- | --- | --- | --- |
| 01 | [01-enums-and-pattern-matching.md](features/01-enums-and-pattern-matching.md) | Complete | Sum types, enum variants, and exhaustive pattern matching. |
| 02 | [02-abstract-types.md](features/02-abstract-types.md) | Planned | Zero-cost abstractions, newtypes, and branded types; the planned value-wrapper extension rules member-carrying abstracts on every target. |
| 03 | [03-structures-and-typedefs.md](features/03-structures-and-typedefs.md) | Complete | Anonymous structures, typedefs, Rust structs, and TypeScript interfaces. |
| 04 | [04-null-safety-and-optionality.md](features/04-null-safety-and-optionality.md) | Complete | Nullable types, optional fields, and strict nullability. |
| 05 | [05-generics.md](features/05-generics.md) | Complete | Parameterized types, constraints, monomorphization, and type erasure. |
| 06 | [06-errors-and-results.md](features/06-errors-and-results.md) | Complete | Exceptions, Result types, and error propagation. |
| 07 | [07-numeric-tower.md](features/07-numeric-tower.md) | Complete | Integer widths, floating-point representations, and conversion rules. |
| 08 | [08-strings-and-unicode.md](features/08-strings-and-unicode.md) | Complete | String representations, UTF-8/UTF-16 encoding, and character indexing. |
| 09 | [09-iterators.md](features/09-iterators.md) | Complete | Iterator protocols, array traversal, and loop transformations. |
| 10 | [10-static-extension.md](features/10-static-extension.md) | Planned | Top-level and extension functions: declaration markers and per-target emission. |
| 11 | [11-inline-and-macros.md](features/11-inline-and-macros.md) | Complete | Inline functions, compile-time macros, and constant folding. |
| 12 | [12-classes-interfaces-access.md](features/12-classes-interfaces-access.md) | Complete | Object-oriented constructs, visibility modifiers, and dispatch. |
| 13 | [13-metadata-and-reflection.md](features/13-metadata-and-reflection.md) | Complete | Compiler metadata tags and reflection limitations. |
| 14 | [14-type-system-mapping.md](features/14-type-system-mapping.md) | Complete | Type identity, nominality, and the fixed cross-language type table. |
| 15 | [15-control-flow.md](features/15-control-flow.md) | Complete | Plain control flow mapping and switch exhaustiveness rules. |
| 16 | [16-static-object-access.md](features/16-static-object-access.md) | Complete | Static object read and write syntax, shape freezing, and behavior parity. |
| 17 | [17-sorting.md](features/17-sorting.md) | Complete | The sort runtime: fixed named strategies, platform bodies, stability identity. |
| 18 | [18-immutability.md](features/18-immutability.md) | Complete | Read-only data types and per-platform mutation enforcement. |
| 19 | [19-testing.md](features/19-testing.md) | Planned | In-source tests, per-target execution, and cross-target consistency. |
| 20 | [20-compile-time-data-tables.md](features/20-compile-time-data-tables.md) | Planned | Compile-time data expansion of large immutable lookup tables and the table emission ruling. |
| 22 | [22-default-argument-expansion.md](features/22-default-argument-expansion.md) | Planned | Optional function parameters with default values: the completion pass in the typed common layer and the call sites that omit them; the planned coalescing-default extension reads earlier parameters and static fields. |
| 23 | [23-float-precision-switch.md](features/23-float-precision-switch.md) | Complete | The `float-precision` define selecting the binary32 mapping of `Float` for the whole compilation, with the TypeScript startup rejection and the f64 wire boundary. |
| 24 | [24-package-shell.md](features/24-package-shell.md) | Complete | The package manifest each target compiler writes next to the generated source, on by default with a one-define opt-out, covering the responsibility split between generator and consumer build. |
| 25 | [25-package-artifacts.md](features/25-package-artifacts.md) | Complete | The pack step behind `package-artifacts=emit`: the compiler writes the ecosystem install artifact (npm tgz, cargo crate, Swift zip, Pub tar.gz) of the tree it emitted, from the recorded write list, with fixed determinism constants. |
| 26 | [26-package-registry.md](features/26-package-registry.md) | Complete | The registry tool that turns a directory of install artifacts into one static, read-only registry site serving the five ecosystems. |
| 27 | [27-class-members-and-records.md](features/27-class-members-and-records.md) | Complete | Class members and records: constructor-parameter fields, constructor bodies, getter-only properties, and the `@:dataClass` record operations. |
| 28 | [28-enum-value-queries.md](features/28-enum-value-queries.md) | Planned | The enum value queries `Type.allEnums`, `Type.enumConstructor`, `Type.createEnum`: compile-time expansion, per-target artifacts, literal count bounds, and miss semantics. |
| 29 | [29-first-class-function-values.md](features/29-first-class-function-values.md) | Planned | Function-typed values in every storage position: the verified renderings on all five targets, Rust boxed function storage, and static function fields with capture-free initializers. |

### Macro specifications

| Number | Specification | Status | Description |
| --- | --- | --- | --- |
| 01 | [01-functional-idiom-expansion.md](macros/01-functional-idiom-expansion.md) | Complete | Closed-list collection pipeline idioms (`map`, `filter`, `forEach`, `associate`, `sortedBy`) expanded into loop forms in the typed common layer. |
| 02 | [02-pipeline-idiom-additions.md](macros/02-pipeline-idiom-additions.md) | Planned | Second closed-list additions: `any`, `all`, `firstOrNull`, `sumOf`, `mapNotNull`, `flatMap`. |
| 03 | [03-group-by-idiom.md](macros/03-group-by-idiom.md) | Planned | `groupBy` with the key-ascending product order. |
| 04 | [04-record-copy.md](macros/04-record-copy.md) | Planned | Record copy with named field overrides, implemented as one Haxe macro. |

### Standard library specifications

| Number | Specification | Status | Description |
| --- | --- | --- | --- |
| 01 | [01-haxe-io-bytes.md](stdlib/01-haxe-io-bytes.md) | Complete | Byte buffer primitives and slice operations. |
| 02 | [02-haxe-io-buffers-and-inputs.md](stdlib/02-haxe-io-buffers-and-inputs.md) | Complete | Sequential buffer writers, stream inputs, and readers. |
| 03 | [03-haxe-exception.md](stdlib/03-haxe-exception.md) | Complete | Standard exception hierarchy and stack trace handling. |
| 04 | [04-haxe-ds-vector.md](stdlib/04-haxe-ds-vector.md) | Complete | Fixed-length dense vector structures. |
| 05 | [05-haxe-int64.md](stdlib/05-haxe-int64.md) | Complete | 64-bit integer representations and emulated arithmetic. |
| 06 | [06-std-modules.md](stdlib/06-std-modules.md) | Complete | The subset's std modules, reserved namespaces, and the runtime package contract. |
| 07 | [07-sorted-keyed-tables.md](stdlib/07-sorted-keyed-tables.md) | Complete | Immutable sorted keyed collections std.SortedMap and std.SortedSet: ordering contract and per-platform shapes. |
| 08 | [08-string-buffer.md](stdlib/08-string-buffer.md) | Complete | Buffered string construction: per-platform mutable accumulators and the code-unit length contract. |
| 09 | [09-inline-arithmetic-helpers.md](stdlib/09-inline-arithmetic-helpers.md) | Complete | Sanctioned static inline helpers for range checks, clamping, and two-field range values. |
| 10 | [10-unicode-string-access.md](stdlib/10-unicode-string-access.md) | Complete | std.UString: code-point-addressed access for strings beyond the ASCII tier. |
| 11 | [11-grapheme-clusters.md](stdlib/11-grapheme-clusters.md) | Complete | std.Graphemes: extended grapheme cluster iteration over code-point content. |
| 12 | [12-std-string.md](stdlib/12-std-string.md) | Complete | Std.string: call-site conversion of scalars, value enumerations, and arrays of them on the five targets, inside concatenation and standalone. |
| 13 | [13-stringtools-conversions.md](stdlib/13-stringtools-conversions.md) | Planned | `StringTools.hex` and the String case conversions on the five targets: call-site native expressions, padding, and the non-negative domain error. |

### Style specifications

| Number | Specification | Status | Description |
| --- | --- | --- | --- |
| 01 | [01-haxe-style-standard.md](style/01-haxe-style-standard.md) | Complete | Haxe style standard for translatable source and the named-violation interception that gates generation. |

### Target specifications

| Target | Specification | Status | Description |
| --- | --- | --- | --- |
| Swift | [swift.md](targets/swift.md) | Rulings complete | The Swift column for every construct the sample tree exercises: value enums, Int32 domain, UTF-16 resident ABI, fault throwing, and the unit-order string comparison. |
| Dart | [dart.md](targets/dart.md) | Rulings complete | The Dart column for every construct the sample tree exercises: sealed fault hierarchies, int domain, native UTF-16 primitives, and the splay-tree sorted collections. |

## Maintenance rule

A translation decision changes only by editing its specification document in the same commit as the code implementing the change. Every ruling additionally satisfies [design-principles.md](design-principles.md), which states the principles a ruling must uphold and the audit tests that review it.
