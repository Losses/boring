# Binary spec 06: Binary record views

## Scope

This specification rules the reading model over a decoded binary record block: how a record is named, how one field is read, how iteration moves from one record to the next, and what is allocated. The byte layout and the derived read functions are ruled in `01-binary-record-layout.md` and `02-binary-record-io.md`; this specification rules the model the read functions serve. The compiler rewrite that supplies the buffer to functions using this model is ruled in `07-binary-record-optimization.md`, and the boundary that converts positions back to values is ruled in `08-binary-record-boundary.md`.

This document rules the requirement and the model. The read functions of binary spec 02 do not exist in the repository yet; today every tree reads through a full decode.

## Requirement

Today decoding materializes one record value for every record: `decode` of `samples/boring/VectorCodec.hx` (lines 127 to 140) allocates one anonymous record plus one nested bounds object per glyph metric, and `decodeVector` of `reference/ts/src/vector-format.ts` (lines 86 to 97) allocates the same two objects per record. A consumer that reads one field of one record pays the decode of every record and the allocation of every record. A consumer that traverses a large table repeatedly pays the allocation again per traversal and keeps a second resident copy of data that already sits in the block.

The reading model of this specification names a record by its position in the block and reads each field directly from the block, with no per-record allocation.

## Model

1. **A record is a position.** A record of the decoded block is named by its position: the byte offset of the record's first byte, held as `GlyphMetricsPos` over `Int` (binary spec 02). Reading one field performs one positional read at the position plus the field's constant offset.
2. **One field read is one buffer read.** With the read function inlined, one field read is one primitive read at a constant offset (`features/10-static-extension.md`, `features/11-inline-and-macros.md`). A nested field reads at the position plus the nested base offset plus the field offset; every term except the position is a constant and folds at compile time.
3. **Iteration is position arithmetic.** The first record sits at position 8, after the header; the next record sits at the current position plus the record width; the record count comes from the header. A traversal holds one position and the buffer, with no per-record object.
4. **Stored links read as integers.** A format may define an `Int` field as a link to another record in the same block. The value 0 means absent. Positions begin at 8, so 0 names no record and the absence check is one comparison. The read functions read a link like any `Int` field; interpreting it as a position is author code.
5. **The block never mutates.** A decoded block is read-only; positions stay valid as long as their buffer is referenced. A position is meaningful only with the buffer it was computed from; the kinds of binary spec 02 keep positions of one format from mixing silently with plain arithmetic, and a position whose buffer a runtime condition chooses carries that buffer in the derived pair of binary spec 07 ruling 10.
6. **Values leave through a copy.** `toRecord(pos)` of binary spec 02 copies one record into a plain value, field by field, deep over nested typedefs. It is the sanctioned path whenever a plain value is required, and binary spec 08 inserts the same copy at the boundary returns.

## Reading shapes compared

### Candidate 1: Positional reads (selected)

Records are positions; field reads are positional reads at constant offsets; iteration is position arithmetic.

- performance: one buffer read per field, zero allocation per record; repeated access decodes once and indexes in constant time.
- ambiguity: a position states the byte it names; the offset states the field it reads.
- redundancy: one read function per field serves every traversal.
- readability: the traversal reads as arithmetic over positions.

### Candidate 2: Decode into record values (status quo)

Every decode materializes one object per record.

- performance: one allocation per record per traversal, plus the decode of every record before the first field is read.
- ambiguity: the record value states its fields.
- redundancy: the materialized array duplicates the block's data in memory.
- readability: consumers read plain values.

### Candidate 3: Lazy record objects

A record object reads fields from the block on demand and caches them.

- performance: one allocation per visited record, plus a cache field per read field; the cache is a second copy of part of the block.
- ambiguity: the object sometimes holds a value and sometimes reads the block, and the two states read the same at the use site.
- redundancy: the cache machinery accompanies every field.
- readability: the consumer cannot see whether a read hits the cache or the block.

### Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| C1 positional reads | one buffer read per field, zero per-record allocation | position plus constant offset | one read function per field | traversal as position arithmetic |
| C2 decode into values | one allocation per record per traversal | plain values | resident duplicate of the block | plain values |
| C3 lazy record objects | allocation per visited record plus caching | cached and uncached states read the same | cache per field | hidden read path |

Principle application: a field read runs at its inherent cost, one buffer load, and a table consulted repeatedly decodes once and answers each lookup with constant-time arithmetic (P3). The restriction of the model, positions are values without their buffer and are held as numbers, carries the sanctioned path of `toRecord` for every place a plain value is required (P2).

## Ruling

1. The reading model over a decoded block is Candidate 1: a record is a position, a field read is one positional read at a constant offset, and iteration advances the position by the record width.
2. The derived read functions of binary spec 02 are the only sanctioned field-read path over a decoded block; renderers and consumers add no field arithmetic of their own beyond the position arithmetic of items 3 and 4.
3. No reading shape allocates per record: a record object over the block exists nowhere in the model, and a plain value enters only through `toRecord` or the boundary conversion of binary spec 08.
4. The accessors of `04-key-index-retrieval.md` and the read functions of this family compute the same offsets: an accessor takes a record index and computes 8 + index x recordWidth + fieldOffset internally; a read function takes the position a caller already holds. One shape serves index-entry consumers, the other serves traversals that walk positions.

## Test hooks

Required once the read functions of binary spec 02 exist; none exist yet:

- Allocation: a traversal reading every field of every record through read functions performs no allocation; a structure test asserts the emitted traversal holds no per-record construction.
- Folding: the emitted code of one read-function call site is one primitive read at a constant offset, with the offset arithmetic folded.
- Agreement: for every field, record index, and width family, the positional read returns the value a full decode returns, the hook binary spec 04 states.
- Stored links: a fixture with link field 0 and link field values naming real positions answers absence with one comparison and resolves the named positions to the expected records.
- Immutability: a decoded block answers identical values across repeated traversals.
