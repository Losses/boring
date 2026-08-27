# Feature spec 20: Compile-time data tables

## Scope

This specification rules how large immutable lookup data enters the
compilation as checked-in data that the compiler expands, with no
handwritten table code. The reference case is the Unicode range table: thousands of sorted integer ranges consulted
through binary search, the shape a character-classification consumer needs
(the tiqian engine carries three such generated tables today:
`UnicodeScriptEvidenceData`, `UnicodeWordCharacterData`, and
`EastAsianSpacingData`, each 730 to 854 lines of checked-in generated
Kotlin). This specification rules three things: the data file format and
the macro that expands a checked-in data file into a constant array
declaration at compile time, the emission form of large constant arrays on
every target, and the amendment this makes to the constant-array unrolling
ruling in `docs/specs/stdlib/04-haxe-ds-vector.md`.

The mechanism uses native Haxe macros only. Compile-time macros that
consume data and construct AST before target emission are the established
architecture (`docs/specs/features/11-inline-and-macros.md`, the
`FormatDef` path in `docs/specs/binary/02-binary-meta-abstraction.md`);
this specification adds no interpreter, no code generator outside the
pipeline, and no runtime dependency.

## Data files

Data lives in `samples/data/` as checked-in text files:

- UTF-8, LF line endings.
- `#` starts a comment line; blank lines are ignored.
- One record per line: whitespace-separated hexadecimal integers, either
  `START END` (a pair) or `START END FLAG` (a triple).
- Records must ascend without overlap: each line's `START` is strictly
  greater than the previous line's `END`.
- A leading comment block records provenance: the upstream source and a
  content hash of the upstream material. Provenance is a review-time
  convention; the macro does not verify it.

The first sample data files carry synthetic range data, labeled as
synthetic in their header comments. The format is unchanged when real
Unicode data arrives; only the provenance block changes.

## The macro

`src/DataTables.hx` declares a top-level macro entry, module shape
matching `src/Intercept.hx`:

```haxe
@:build(DataTables.rangesField("samples/data/synthetic-script-ranges.txt", "RANGES"))
class ScriptEvidenceTable { ... }
```

- `DataTables.rangesField(path, fieldName)` runs as a `@:build` macro on
  the class. It reads the file with `sys.io.File` on the host
  interpreter, validates it, and adds one static final field of type
  `Array<Int>` holding the flattened records in file order (pairs:
  `s0, e0, s1, e1, ...`; triples: `s0, e0, f0, s1, ...`).
- Validation failures are compile errors that name the file and the
  offending line: records out of ascending order or overlapping, values
  outside the signed 32-bit `Int` range, a line with the wrong field
  count for the file's layout (the layout is fixed by the first data
  line), and an empty file. The macro infers pair-versus-triple layout
  from the first record and rejects mixed lines.
- The output is a pure function of the file bytes. The macro emits the
  array literal; it does not generate lookup functions, does not read
  the environment, and does not record time or path-dependent state.
- The macro is product: it sits in `src/` beside `Intercept.hx` and is
  available to every consumer of the package.

## Table emission and the unrolling amendment

A constant array whose element count is 64 or fewer follows the unrolling
ruling of `docs/specs/stdlib/04-haxe-ds-vector.md` unchanged. A constant
array of `Int` with more than 64 elements is a **data table** and takes
the index-computed storage form on each target:

| Target | Form | Notes |
| --- | --- | --- |
| Rust | `static RANGES: [u32; N] = [...];` | Read-only memory, no runtime initialization; visibility per the field's declared access. The element type follows the Rust target's existing `Int` mapping (`u32`, `src/reflaxe/rust/rustcompiler/RustType.hx`). |
| TypeScript | `const RANGES = new Int32Array([...]);` | Packed 4-byte elements; indexed reads yield `number`. |
| Kotlin | `val RANGES = intArrayOf(...)` inside the object | One allocation at class initialization; Kotlin declares no `const` arrays, recorded in `docs/specs/stdlib/04-haxe-ds-vector.md`. |

Index reads into a table follow the platform's existing read rules; in
particular TypeScript keeps the non-null assertion discipline of
`docs/specs/features/09-iterators.md` for reads the surrounding code
establishes as in-bounds.

`docs/specs/stdlib/04-haxe-ds-vector.md`'s unrolling paragraph gains:
index-computed lookup tables are outside the unrolling ruling; constant
arrays over 64 elements follow the data-table emission of this
specification. The unrolling paragraph's consumer is the wire payload,
whose elements a fixed-order loop consumes; a table's elements are
reached by computed index, which per-element constants cannot express.
The 64-element threshold separates the two populations with margin on
both sides; a wire payload that grows past it is a specification-level
event and returns here.

Runtime-built arrays of any size are unaffected: unrolling and table
emission apply to compile-time constant arrays only.

## Lookup logic

The macro expands data; the algorithm stays handwritten. Binary search
over the flattened table is ordinary translatable-subset code: a `while`
loop, computed index access, no closures, no function values. Keeping
the lookup in sample source leaves the algorithm visible and auditable
and gives the pipeline a real expression of index-computed access to
typecheck and emit.

## Sample

`samples/boring/` gains two table classes, one per layout:

- `ScriptEvidenceTable.hx`: a triples table; `classify(codePoint:Int)`
  returns the flag of the covering record or `0` on miss, by binary
  search.
- `WordCharacterTable.hx`: a pairs table; `contains(codePoint:Int)`
  returns whether a record covers the code point, by binary search.

Both data files are synthetic, carry provenance comments stating so, and
cross the 64-element threshold so the sample exercises table emission.

## Tests

- `tests/ts/` gains a generated-tree assertion: the TypeScript output
  contains the `Int32Array` table form for the sample tables and no
  per-element constant unrolling for them.
- Under the testing standard `docs/specs/features/19-testing.md`,
  `samples/tests/` gains `std.Test` cases over both tables: hits at the
  first and last record, misses immediately below and immediately above
  the covered span, boundary values at record edges, and a flag lookup.
  Cross-target equality runs through the consistency manager like every other test module.
- Mutation evidence: a one-line change to a data file changes the
  regenerated table on all three targets.

## Not in scope

Sorting at build time, keyed structures, and any mutable table: the
keyed-lookup structure is ruled separately in
`docs/specs/stdlib/07-sorted-keyed-tables.md`. Hash-based lookup appears
nowhere in either ruling.
