# Standard library spec 11: std.Graphemes

## Scope

This specification provides the grapheme cluster tier above the
code-point tier of `docs/specs/stdlib/10-unicode-string-access.md`.
A grapheme cluster is a user-perceived character under UAX #29: a base
character with its combining marks, a Hangul jamo run, a carriage
return and line feed pair, an emoji sequence with modifiers, joiners,
or keycap marks, a regional-indicator pair, or an Indic conjunct. The
module answers the question of how many characters a reader sees, which
no storage unit and no code-point count answers: the family emoji
sequence is seven code points, eleven UTF-16 units, and one grapheme
cluster.

## Contract

`std.Graphemes` is a module of static functions over the grapheme
clusters of a string. The input domain is valid Unicode scalar
sequences, the same domain `stdlib/10` states.

| Function | Contract |
| --- | --- |
| `count(s:String):Int` | The number of grapheme clusters. |
| `at(s:String, index:Int):Null<String>` | The cluster at position `index`, counting from 0; `null` when `index` is negative or at least `count(s)`. The null return on a miss matches `String.charCodeAt` and `stdlib/10 at`. |
| `slice(s:String, from:Int, to:Int):String` | The clusters from position `from` inclusive to `to` exclusive. `from` clamps upward to 0, `to` clamps downward to `count(s)`, and `from >= to` yields the empty string. The clamping contract matches `stdlib/10 slice`. |
| `parts(s:String):Array<String>` | One array element per cluster, in order. |

No function throws. An out-of-range `at` is a query miss and returns
null, the same ruling as `stdlib/10`.

## Judgment

The boundary rules are the extended grapheme cluster rules of UAX #29:
GB1 through GB13 and GB999, including GB9c (Indic conjuncts, Unicode
15.1) and GB11 (emoji joiner sequences). Three implementation shapes
were considered:

1. **Platform segmentation APIs.** `Intl.Segmenter` on JavaScript,
   `java.text.BreakIterator` on the JVM, and ICU on Rust follow the ICU
   build of each host, so the same input segments differently across
   hosts and across host versions. This defines the operation's meaning
   by the platform implementation, which the design principles reject,
   and it breaks four-target equality by construction.
2. **A rule set per target.** Four independent implementations of the
   rule table drift apart silently; nothing pins them to one another.
3. **One generated table and one rule walk shared by all targets**
   (this specification). The break properties come from one pinned
   Unicode release, one tool merges them into a flat range table, every
   target reads the same table through the same lookup, and the official
   Unicode conformance file gates the generation.

Cost floors, recorded per the design principles:

| Usage pattern | Operation | Cost |
| --- | --- | --- |
| Cluster count | `count` | one pass, one table lookup per code point, no allocation |
| One cluster query | `at` | one pass or less, no allocation beyond the result |
| Cluster substring | `slice` | one pass plus the result string |
| Repeated cluster access | `parts`, then array indexing | one pass plus the output array, then constant time |

The table lookup is a binary search over 1965 disjoint ranges for
Unicode 17.0.0, eleven comparisons per code point; the walk state is
one integer. Segmentation must classify every code point at least once,
so the one-pass shape sits at the floor. Rust iterates UTF-8 `chars()`,
the UTF-16 platforms walk code units, and each target costs the same
order, per the storage ruling of `stdlib/10`.

## Data, tooling, and regeneration

The break data comes from three files of one Unicode release plus the
official conformance file, committed under `tools/unicode-data/` with
version-suffixed names:

- `GraphemeBreakProperty.txt`: the twelve Grapheme_Cluster_Break
  classes.
- `emoji-data.txt`: Extended_Pictographic, which rule GB11 reads.
- `DerivedCoreProperties.txt`: the three Indic_Conjunct_Break values,
  which rule GB9c reads.
- `GraphemeBreakTest.txt`: the official boundary conformance vectors.

The table is built at compilation start by the macro module
`src/reflaxe/unicode/GraphemeData.hx`
(`docs/plans/2026-08-28-runtime-unification.md` P2). It parses the
three property files with `sys.io.File`, merges them into disjoint
code-point ranges, and hands the table to the consumers in the same
compilation: the target compilers render it into their runtime
packages (`GraphemeTableRender`), and
`--macro reflaxe.unicode.GraphemeData.ensureType()` defines the class
`reflaxe.unicode.GraphemeBreakData` for sources that reference the
table as a Haxe class. The table layout is one flat int array with
three ints per range (start, endInclusive, packed), where the packed
value carries the Grapheme_Cluster_Break class in bits 0-3,
Extended_Pictographic in bit 4, and Indic_Conjunct_Break in bits 5-6.
Code points absent from the table are class Other with no flags.
Nothing generated is committed.

The merge refuses to produce a table unless every line of the pinned
`GraphemeBreakTest.txt` passes under the table and the shared walk in
`src/reflaxe/unicode/GraphemeWalk.hx`. The walk packs its carried state
into one integer: the GB11 link stage in bits 0-1 (armed only while the
text ends in Extended_Pictographic, Extend run, then ZWJ), the GB9c
link stage in bits 2-3 (armed after a Consonant and an Extend or Linker
run that contains at least one Linker), and the regional-indicator
parity in bit 4. A conformance failure aborts the compilation.

A content-hash cache under `out/unicode-cache/` keys the merged table
on the hash of the four input files, so ordinary compilations skip
parsing and conformance; any change to the pinned data re-runs the full
gate. Ordinary compilation is network-free and reads the pinned files.
Moving to a later Unicode release runs the compilation with
`-D fetch-unicode=<version>`, which downloads the four files of that
release from unicode.org into `tools/unicode-data/` before parsing and
enforces the same conformance gate; the refresh is one commit that
carries the four data files, the pin constant, and nothing else.
Builds without the define never read the network. The download runs
curl as a subprocess from the macro: the chunked-transfer decoder of
`sys.Http` in Haxe 4.3.7 discards misaligned bytes when TCP
segmentation splits a chunk header, which corrupts these files
nondeterministically, and the conformance gate rejects the corrupt
downloads.

## Haxe declarations and routing

`samples/std/Graphemes.hx` declares the extern class with the four
static functions, following the `SortedMap` pattern of
`docs/specs/stdlib/06-std-modules.md`. The module has no construction
domain and no fault enum, so it has no wrapper tier and no RT twin;
references route through the target import tables into the runtime
package. `stdlib/06` lists `std.Graphemes` among the runtime-backed std
modules, and the class lists live in `TsImports.runtimeProvidedModules`
and `KotlinImports.SHIM_MODULES`.

The stage-one oracle is `tests/haxe/GraphemesOracle.hx`, a haxe
implementation of the cluster tier over the shared
`reflaxe.unicode.GraphemeWalk` and the macro-defined
`GraphemeBreakData.TABLE`. The generated test runner and the typed
harness bind it to `globalThis.std.Graphemes`, the binding pattern of
`stdlib/10`.

## Per-platform shapes

- Rust: `graphemes.rs` in the runtime package. The table is a
  `static GRAPHEME_TABLE: [u32; N]`; the walk iterates `chars()` with
  `char_indices` for slicing; `count` returns `u32`, `at` returns
  `Option<String>`, `parts` returns `Vec<String>`.
- TypeScript: the `Graphemes` object in `runtime.ts`, preceded by the
  table as `export const GRAPHEME_TABLE = new Int32Array([...])`. The
  walk reads `codePointAt` and advances one or two units per code
  point.
- Kotlin: `Graphemes.kt` in the runtime package, with the table as a
  file-level `private val GRAPHEME_TABLE: IntArray`. The walk reads
  `charAt` unit widths, the same shape as the `UString` shim.
- Stage-one haxe: the oracle of the routing section, one implementation
  of the same walk.

Every target names the rules it applies (comments cite GB3 through
GB999) and reads the same packed classes; the four-target consistency
run compares the outputs.

## Samples and tests

`samples/boring/GraphemeOps.hx` routes every operation through
`std.Graphemes` with `std.UString` beside it for the code-point
contrast. `samples/tests/GraphemeTests.hx` covers the rule families:
BMP CJK; combining marks joined to their base (GB9); Hangul jamo runs
and precomposed syllables (GB6 through GB8); the CR LF pair (GB3);
emoji joiner, modifier, and keycap sequences (GB9, GB9a, GB11);
regional-indicator pairing (GB12 and GB13); Devanagari conjuncts with
and without a second consonant (GB9c); a Prepend character (GB9b); and
the slicing and parts contracts, including clamping and the empty
string. Assertions state both the cluster count and the code-point
count where the two differ.

The compile-time gate replaces the committed-table revalidation test:
the table exists only as the output of the macro pipeline over the
pinned files, so a stale or hand-edited table cannot be expressed. The
four-side consistency run compares jsonl output over the sample suite.
