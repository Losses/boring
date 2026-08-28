# Macro spec 04: Record copy

## Scope

This specification rules the record copy construct: creating a new record
value from an existing one with zero or more fields replaced. The engine
port audit carries 47 uses on data-class records. The construct is not a
Haxe language feature; it is a boring-provided compile-time rewrite,
implemented as one Haxe macro that runs during typing, so the stage-one
build and the three generation compiles execute the same single
implementation.

## Source form

```haxe
typedef Item = { id:Int, name:String, score:Int };

var updated = item.copy(score = 99);
var same = item.copy();
```

Every argument must parse as an assignment expression whose left side is
a plain identifier and whose right side is an arbitrary expression. Any
other argument shape is rejected with the named error
`record copy overrides assign fields by name only`. Each identifier must
be a field of the receiver's structure type; an unknown name is rejected
with the named error
`record copy overrides fields of the receiver record only`.

Because the construct borrows the assignment-expression syntax, the style
standard bans assignment expressions as call arguments everywhere else;
the `V17 AssignArgExpression` row of
`docs/specs/style/01-haxe-style-standard.md` records the ban.

## Expansion

The macro reads the receiver's typed structure, enumerates its fields in
declaration order, and produces one structure literal: every field reads
the receiver, and an overridden field uses its argument expression. The
receiver must be an anonymous structure type per
`docs/specs/features/03-structures-and-typedefs.md`; a class receiver is
rejected with the second named error above.

Override expressions evaluate in the receiver's field-declaration order,
and each evaluates at most once.

The product is an expression and composes in every expression position,
so the position rule and mint naming of `macros/01` do not apply and the
pipeline expansion pass holds no copy knowledge.

## Oracle standing

The macro runs inside the Haxe compiler for the stage-one build and for
each generation compile, so all four sides execute the same rewrite. The
four-side consistency run of `docs/specs/features/19-testing.md` checks
the downstream emission of the produced literal, and no side runs an
independent expansion; this tier is weaker than a standard-library oracle
and this specification records that.

## Test hooks

- A sample module copies a record with no override, with one override,
  and with overrides whose argument order differs from the declaration
  order, and asserts every field of each product.
- The four-side consistency run compares the jsonl output.
- `tests/ts/` tree assertions pin the products: generated trees contain
  no `.copy(` call sites, and each product appears as the full structure
  construction.
- The mutation checks for this module live in the dispatch task file.
