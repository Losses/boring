# Translation specifications

This directory defines the translation rules from Haxe into Rust, TypeScript, and Kotlin for the boring repository.

## Purpose

The repository hosts one binary codec implemented in Haxe, Rust, TypeScript, and Kotlin. Haxe is the reference language. Every Haxe construct used by the codec requires an explicit, written translation rule for Rust, TypeScript, and Kotlin.

The Kotlin tree is present under `kotlin/`. The Kotlin rulings in these specifications bind the Reflaxe generator when it emits a Kotlin target, so the target arrives with its translation decisions already written down.

A later compilation and generation stage produces or verifies target code against these specifications. Without written specifications, unit tests inherit ad hoc translation choices, and disagreements in emitted bytes cannot be localized to a single design decision. Each specification document serves as the single location where a translation decision is defined and justified.

## Classification

Specifications are organized into four categories:

1. `binary/`: Rules governing binary encapsulation and wire format mechanics. Each file rules one mechanism across the entire format.
2. `features/`: Rules governing Haxe language constructs. Each file defines the syntax, semantics, typed-AST representation, and cross-language mappings for one construct.
3. `stdlib/`: Rules governing Haxe standard library modules and functions. These documents define standard library substitutions for the target languages.
4. `style/`: Rules governing the Haxe source standard itself and the interception that enforces it before generation.

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
| 01 | [01-wire-format.md](binary/01-wire-format.md) | Complete | Byte layout, endianness, record packing, and dyadic rational precision. |
| 02 | [02-binary-meta-abstraction.md](binary/02-binary-meta-abstraction.md) | Complete | Typed meta-level format representation and Reflaxe generator integration. |
| 03 | [03-diff-localization.md](binary/03-diff-localization.md) | Complete | Offset calculation and mapping byte diffs to encoder functions. |
| 04 | [04-key-index-retrieval.md](binary/04-key-index-retrieval.md) | Complete | Generated per-key accessors reading fields at build-time offsets. |

### Language feature specifications

| Number | Specification | Status | Description |
| --- | --- | --- | --- |
| 01 | [01-enums-and-pattern-matching.md](features/01-enums-and-pattern-matching.md) | Complete | Sum types, enum variants, and exhaustive pattern matching. |
| 02 | [02-abstract-types.md](features/02-abstract-types.md) | Complete | Zero-cost abstractions, newtypes, and branded types. |
| 03 | [03-structures-and-typedefs.md](features/03-structures-and-typedefs.md) | Complete | Anonymous structures, typedefs, Rust structs, and TypeScript interfaces. |
| 04 | [04-null-safety-and-optionality.md](features/04-null-safety-and-optionality.md) | Complete | Nullable types, optional fields, and strict nullability. |
| 05 | [05-generics.md](features/05-generics.md) | Complete | Parameterized types, constraints, monomorphization, and type erasure. |
| 06 | [06-errors-and-results.md](features/06-errors-and-results.md) | Complete | Exceptions, Result types, and error propagation. |
| 07 | [07-numeric-tower.md](features/07-numeric-tower.md) | Complete | Integer widths, floating-point representations, and conversion rules. |
| 08 | [08-strings-and-unicode.md](features/08-strings-and-unicode.md) | Complete | String representations, UTF-8/UTF-16 encoding, and character indexing. |
| 09 | [09-iterators.md](features/09-iterators.md) | Complete | Iterator protocols, array traversal, and loop transformations. |
| 10 | [10-static-extension.md](features/10-static-extension.md) | Complete | Static extension methods and target method dispatch. |
| 11 | [11-inline-and-macros.md](features/11-inline-and-macros.md) | Complete | Inline functions, compile-time macros, and constant folding. |
| 12 | [12-classes-interfaces-access.md](features/12-classes-interfaces-access.md) | Complete | Object-oriented constructs, visibility modifiers, and dispatch. |
| 13 | [13-metadata-and-reflection.md](features/13-metadata-and-reflection.md) | Complete | Compiler metadata tags and reflection limitations. |
| 14 | [14-type-system-mapping.md](features/14-type-system-mapping.md) | Complete | Type identity, nominality, and the fixed cross-language type table. |
| 15 | [15-control-flow.md](features/15-control-flow.md) | Complete | Plain control flow mapping and switch exhaustiveness rules. |
| 16 | [16-static-object-access.md](features/16-static-object-access.md) | Complete | Static object read and write syntax, shape freezing, and behavior parity. |
| 17 | [17-sorting.md](features/17-sorting.md) | Complete | The sort runtime: fixed named strategies, platform bodies, stability identity. |
| 18 | [18-immutability.md](features/18-immutability.md) | Complete | Read-only data surfaces and per-platform mutation enforcement. |

### Standard library specifications

| Number | Specification | Status | Description |
| --- | --- | --- | --- |
| 01 | [01-haxe-io-bytes.md](stdlib/01-haxe-io-bytes.md) | Complete | Byte buffer primitives and slice operations. |
| 02 | [02-haxe-io-buffers-and-inputs.md](stdlib/02-haxe-io-buffers-and-inputs.md) | Complete | Sequential buffer writers, stream inputs, and readers. |
| 03 | [03-haxe-exception.md](stdlib/03-haxe-exception.md) | Complete | Standard exception hierarchy and stack trace handling. |
| 04 | [04-haxe-ds-vector.md](stdlib/04-haxe-ds-vector.md) | Complete | Fixed-length dense vector structures. |
| 05 | [05-haxe-int64.md](stdlib/05-haxe-int64.md) | Complete | 64-bit integer representations and emulated arithmetic. |

### Style specifications

| Number | Specification | Status | Description |
| --- | --- | --- | --- |
| 01 | [01-haxe-style-standard.md](style/01-haxe-style-standard.md) | Complete | Haxe style standard for translatable source and the named-violation interception that gates generation. |

## Maintenance rule

A translation decision changes only by editing its specification document in the same commit as the code implementing the change.
