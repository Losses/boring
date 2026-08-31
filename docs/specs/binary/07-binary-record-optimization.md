# Binary spec 07: Binary record optimization

## Scope

This specification rules the compiler rewrite that supplies the record buffer to the functions that read positions: which functions the rewrite marks, what it adds to them, where it stops, and the shapes it rejects. The reading model the rewrite serves is ruled in `06-binary-record-views.md`; the buffer kinds, the position types, and the read functions are ruled in `02-binary-record-io.md`; the declarations whose signatures the rewrite leaves as authored are ruled in `08-binary-record-boundary.md`.

The rewrite runs in the typed common layer, the same layer as the completion pass of `features/22-default-argument-expansion.md`, before any target compiler runs. It changes three things in the program: parameter lists, call-site argument lists, and, where a runtime condition chooses between buffers of one kind, the merged storage's type and its pair constructions (ruling 10).

This document rules the rewrite. Neither the read functions of binary spec 02 nor this pass exists in the repository yet.

## Requirement

Under the reading model of binary spec 06, every field read needs the record buffer the position belongs to. Written by hand, the buffer parameter would appear on every function of a traversal chain, including every intermediate function that passes the buffer along without reading it. The rewrite derives the parameter set from the call graph, so the author states positions and fields and the compiler states the buffer.

## Source and rewritten form

Author source, with the read functions of binary spec 02 in scope:

```haxe
static function readAdvance(pos:GlyphMetricsPos):Float {
	return advanceEm(pos);
}

static function sumAdvances(first:GlyphMetricsPos, count:Int):Float {
	var total = 0.0;
	var pos = first;
	for (index in 0...count) {
		total += readAdvance(pos);
		pos = next(pos);
	}
	return total;
}
```

After the rewrite, both functions carry one trailing `buffer` parameter of the needed kind, the internal call appends the argument, and the inlined read function body performs one positional read:

```haxe
static function readAdvance(pos:GlyphMetricsPos, buffer:GlyphMetricsBuffer):Float {
	return buffer.readF64((pos : Int) + 4);
}

static function sumAdvances(first:GlyphMetricsPos, count:Int, buffer:GlyphMetricsBuffer):Float {
	var total = 0.0;
	var pos = first;
	for (index in 0...count) {
		total += readAdvance(pos, buffer);
		pos = next(pos);
	}
	return total;
}
```

Two further shapes. Two position parameters of one kind contribute two buffers, one per stream:

```haxe
static function compareAdvance(posA:GlyphMetricsPos, posB:GlyphMetricsPos):Float {
	return advanceEm(posA) - advanceEm(posB);
}
```

```haxe
static function compareAdvance(posA:GlyphMetricsPos, posB:GlyphMetricsPos, bufferA:GlyphMetricsBuffer, bufferB:GlyphMetricsBuffer):Float {
	return advanceEm(posA, bufferA) - advanceEm(posB, bufferB);
}
```

A runtime condition that chooses between two buffers of one kind merges the streams (`hasGlyph` is author code), and the rewrite returns the derived pair of ruling 10:

```haxe
static function pick(primary:GlyphMetricsBuffer, fallback:GlyphMetricsBuffer, codePoint:Int):GlyphMetricsPos {
	if (hasGlyph(primary, codePoint)) {
		return positionOf(primary, codePoint);
	}
	return positionOf(fallback, codePoint);
}
```

```haxe
static function pick(primary:GlyphMetricsBuffer, fallback:GlyphMetricsBuffer, codePoint:Int):GlyphMetricsRef {
	if (hasGlyph(primary, codePoint)) {
		return new GlyphMetricsRef(primary, positionOf(primary, codePoint));
	}
	return new GlyphMetricsRef(fallback, positionOf(fallback, codePoint));
}
```

## Threading shapes compared

### Candidate 1: Implicit threading (selected)

The compiler scans which functions read positions and adds one implicit buffer parameter per position stream to each of them, updating every call site.

- performance: a buffer reference is one machine word per call; inlined read functions fold to single buffer reads.
- ambiguity: the author never writes the threading; the reading direction is the call direction.
- redundancy: one derived parameter set serves every entry.
- readability: source states data relationships and omits the passing machinery.

### Candidate 2: Explicit buffer parameter in source

Authors write the buffer parameter on every position-reading function by hand. No compiler change.

- performance: as Candidate 1.
- ambiguity: the parameter is visible and greppable.
- redundancy: every intermediate function repeats the parameter without using it directly.
- readability: the added parameter occupies signatures the reader skips at every level of a deep call chain.

### Candidate 3: Buffer id in the position's high bits

The position and a buffer id share one `Int`; a global table maps ids to buffers; arithmetic carries the id. No compiler change.

- performance: every position operation masks the id; the global table adds one indirection per buffer recovery.
- ambiguity: a position value mixes two fields in one integer.
- redundancy: none.
- readability: the caps, 24-bit positions scaled by 4-byte alignment and 256 live buffers, are invariants the source does not state; the Rust target needs a global table the borrow checker charges for at every recovery.

### Candidate 4: Position as a (buffer, position) pair

Every position value carries both fields; full inlining keeps reads flat.

- performance: every non-inline boundary moves one small object per position value passed.
- ambiguity: the pair is explicit.
- redundancy: the buffer field repeats on every position of one buffer.
- readability: as Candidate 2, the pair appears in every signature.

Ruling 10 returns this candidate in a bounded role: the compiler inserts the pair where a runtime condition chooses the buffer, and authored position values carry no buffer everywhere else. The universal form stays rejected on the performance and redundancy rows above.

### Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| C1 implicit threading | one word per call; reads fold to single loads | added parameters absent from source | one derived parameter set | data relationships only |
| C2 explicit parameter | as C1 | parameter greppable | repeated per function | added parameter on every level |
| C3 high-bit id | mask per operation; table indirection | two fields in one Int | none | unstated caps |
| C4 pair value | one object moved at each boundary | pair explicit | buffer field repeated | pair in every signature |

Principle application: C1 is selected on author-facing semantics and on per-read cost, and stands with the compiler's implementation cost treated as its own work item, charged to no ruling (P4). Field reads run at their inherent cost, one buffer load per field (P3). The restriction of ruling 11 carries a sanctioned path: keep the call direct (P2). Ruling 10 resolves a runtime choice between buffers inside the rewrite by the compiler-inserted pair, the bounded return of Candidate 4, so no sanctioned path is needed there.

## Ruling

1. **Scan.** Pass one marks every function that touches a position: a function whose body declares a position-typed local or parameter, calls a read function, calls a function already marked, or names a buffer kind in a read. The mark closes over the call graph. The pass runs in the typed common layer, before target emission.
2. **Parameters.** Pass two adds to each marked function one implicit buffer parameter per unbound position stream of ruling 10, appended after the author's parameters, carrying the buffer kind. When one function touches several kinds, each kind contributes its own parameters; when one function receives several streams of one kind, each stream contributes its own parameter. Call sites of rewritten functions append one buffer argument per stream in parameter order. The completion of `features/22-default-argument-expansion.md` and this rewrite compose: default arguments complete first, then the buffer arguments append.
3. **Binding stops.** A function that already declares a parameter of the needed buffer kind binds the position reads of that parameter's stream to it, and the rewrite adds nothing for that stream; under the deep check of binary spec 08 that declaration is a system declaration, because its signature names a buffer kind. A foreign-facing declaration keeps the shape of its signature as authored, and the rewrite appends no parameter to it. A foreign-facing function that reads positions obtains its buffer through an authored `RecordBuffer` parameter, bound to the needed kind through the kind's implicit cast, or through construction from its own `haxe.io.Bytes` parameter. A foreign-facing function with neither stops the compilation with `foreign-facing function reads positions without a record buffer parameter: add the parameter or return materialized values`, naming the function. Fixing the signature is an API design act; this is the only shape the rewrite rejects in a foreign-facing declaration.
4. **Methods and constructors.** A constructor is a function. A position-reading constructor gains each implicit parameter as a field plus a constructor parameter, and every construction site appends the arguments. A method of a class holding one or more fields of the needed buffer kind binds the position reads of each field's stream to that field, and the rewrite adds no parameter for that stream. A class that gained a field through its constructor provides that binding to all of its methods.
5. **Override families.** When one member of an override family touches positions, the implicit parameters of its streams are added to the root declaration and to every override. An interface method whose implementations read positions gains the parameters on the interface declaration, so dispatch through the interface carries the buffers.
6. **The implicit name.** Inside the body of a function that the rewrite supplies with a buffer of kind K, `buffer` names that binding; inside a body with several kinds or several streams of one kind, `buffer` names the binding of the surrounding read's position operand, resolved by that operand's stream. Read-function bodies are the intended use; general internal functions receive their buffer through parameters and pass it on at call sites. An author parameter named `buffer` whose type is a buffer kind is the explicit binding of ruling 3; an author parameter named `buffer` of any other type inside a position-reading function stops the compilation with `the name buffer is reserved for the implicit record buffer parameter`.
7. **Locals and chains.** The rewrite changes parameter lists, call-site argument lists, and the merged storage types with their constructions of ruling 10, and nothing else. Positions stored in local variables flow by value, so `var p = next(p); use(p)` needs no handling. Single-expression chains rewrite each call site on the chain, and the chain head is an entry that already carries its buffer.
8. **Recursion.** A recursive function rewrites once and passes its own binding to itself on the recursive edges.
9. **Reading direction.** The user-facing model reads from the leaf upward: the leaf function needs the buffer of its positions' stream, each caller above supplies it, and the topmost author-written entry declares it as an ordinary parameter. The implementation discovers the set by a fixpoint over the call graph; the discovery order is invisible in the source.
10. **Streams and runtime-chosen buffers.** For every position value the rewrite tracks the buffer expression that produced it; that fact is the value's stream. A stream originating at an authored buffer parameter binds to it (ruling 3); a stream originating at a class field of the enclosing class binds to it (ruling 4); a stream entering through a position parameter of the function contributes one implicit buffer parameter of the kind, appended after the author's parameters in the order of the position parameters, and two position parameters of one kind contribute two implicit parameters. A call site appends one buffer argument per stream in the same order, and one buffer passed to two streams is legal. A storage location that receives positions from two or more streams of one kind under a runtime condition is merged: the rewrite stores the pair instead. The compiler derives one pair type per kind, `<Name>Ref`, holding `buffer` of the buffer kind and `pos` of the position type; every merge site, at a return value, an array element, a local variable, or an object field, constructs the pair from its branch's buffer and position, the merged location's declared type becomes the pair type, and a read through a merged value reads the two members. The rewrite changes signatures and call sites of merged values freely inside the system; foreign-facing declarations are untouched, because a position type or a pair type in a signature already places the declaration in the system tier of binary spec 08, and the boundary conversion of that specification runs before any consumer sees the value. The error `two record buffers of one kind are in scope` is withdrawn. Declaring a second annotated format with the same fields and a distinct stem remains available to an author who wants two buffers checked as distinct types; it is an option, no longer a requirement.
11. **Function values.** A position-reading function referenced as a value stops the compilation with `a position-reading function cannot be used as a value: the implicit record buffer parameter cannot thread through a function value`. The V02 rejection of `macros/01-functional-idiom-expansion.md` already removes most value uses; this rule names the residue.

## Test hooks

Required once the rewrite exists; none exist yet:

- The sample tree gains a fixture block with a header at position 0, fixed-layout records, and absent (0) stored links, shared by every lane.
- One lane asserts the folded read emission, one buffer read at a constant offset; the threaded signatures and call sites of a chain four records deep; the constructor field and its construction sites; the override family; the recursive function; and the explicit-binding stop.
- One lane asserts the stream expansion: a function reading two position parameters of one kind carries two implicit buffer parameters, its call sites append both, and one buffer serves two streams at a call site holding one buffer.
- One lane asserts the merged pair: a function returning the position a runtime condition chooses between two buffers of one kind returns the derived `<Name>Ref` with one construction per branch, the caller reads through both members, and an array receiving positions of two streams changes its element type to the pair type.
- Rejection tests for the named errors of rulings 3, 6, and 11.
- A compilation with no position types emits byte-identical output to the emission before this specification, guarding the opt-in nature of the rewrite.
