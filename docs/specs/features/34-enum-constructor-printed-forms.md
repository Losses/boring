# Feature spec 34: Enum constructor printed forms

Status: Implemented. This specification amends the Contract domain and the
rejection sentence of [12-std-string.md](../stdlib/12-std-string.md) as
restated by [33-record-collection-fields.md](33-record-collection-fields.md),
and adds one sentence to ruling 4 of
[31-record-tostring-member.md](31-record-tostring-member.md).

## Scope

This specification rules the printed form of enum operands of `Std.string`
and of enum-typed fields in the record member synthesis. Parameterless
enums print through their constructor-name reads, the reads stdlib spec 12
already rules; payload enums print a labeled constructor form
`Name(param=value, ...)` built from the constructor parameter names the
compiler holds.

The engine port is the consumer. `RichTextSpan` holds
`role:RichTextRole` (`engine-haxe/src/org/tiqian/core/RichTextSpan.hx`);
`RichTextRole` declares five parameterless constructors and
`Link(target:String)`; the Kotlin original prints `Link(target=...)`
through its `data class` synthesis, and the port keeps an explicit member
with a handwritten switch spelling the labels. Records with parameterless
enum fields (`FontMetricsRequest` holds `role:FontRole`) print through the
enum forms this specification rules. Every ported record with an enum
field joins the same shape.

This specification rules all five source targets (ts, kotlin, swift, dart,
rust) together; the f32 configurations inherit the rules and differ only in float
width.

## Current state

| Operand | TypeScript | Kotlin | Swift | Dart | Rust |
| --- | --- | --- | --- | --- | --- |
| parameterless enum value through `Std.string` | the `kind` read | the name through the enum `toString` | the `rawValue` read | the `label` read | the `name()` read |
| parameterless enum record field, bare read in `+` | the object form | the name (native coercion) | the lower-cased case name | the target-mangled name | no `Display` implementation; the tree does not compile |
| payload enum operand of `Std.string` | rejected with the named error | same | same | same | same |

The record assembly renders an enum-typed field as the bare field read
(`samples/std/RecordShape.hx`, `assemble`), so the parameterless row prints
four different texts and the payload row has no legal operand at all; the
port works around both with explicit members.

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Labeled constructor form through an exhaustive branch at the operand position | One discrimination per render: a conditional chain over the constructors on the structural targets, the native member dispatch on Kotlin, a `match` on Rust; no closure runs and no intermediate collection exists. | One ruled text; the labels are the constructor parameter names the declaration carries. | The branch reuses the constructor reads and case bindings the pattern rules of features/01 already lower; no resident helper exists to keep in sync. | Each arm reads as the labeled text it prints. |
| Rely on the target-native printed form | Kotlin prints the ruled text natively (the `data class` and `data object` members of the features/01 payload form); the other four targets print four different texts (an object form, a lower-cased case, a mangled name, no `Display`). | Five texts for one value; stdlib spec 12 rejects this for scalars and arrays on the same ground. | Nothing to implement. | Sites read differently per target. |
| A resident stringify helper per target | One helper call per operand. | The helper invents its own rendering rules per target. | Five helpers for one form. | Sites read as a library call the target spells shorter. |
| The port hand-writes the switch per record | No compiler work. | Every consumer re-decides the labels. | One switch per record; `RichTextSpan` today. | The port source drifts from the Kotlin original. |

## Ruling

1. The operand domain of stdlib spec 12 admits payload enums. A payload
   enum operand renders the labeled constructor form `Name(param=value,
   ...)` with the arguments in constructor parameter order and `", "`
   between them; a parameterless constructor of a payload enum renders
   its bare constructor name. The rejection sentence of stdlib spec 12,
   as amended by feature spec 33, drops the payload-enum clause, and the
   named error becomes `Std.string accepts scalars, enum values, records,
   and arrays of them only`; the probes assert the new text. The tables
   of stdlib spec 12 rulings 2 and 3 gain the payload-enumeration row
   with the forms of ruling 2 below.
2. Per target, `Std.string(mark)` over a payload enum renders:

   | Target | rendering |
   | --- | --- |
   | Kotlin | the bare operand in concatenation and `mark.toString()` standalone; the sealed-variant forms of features/01 print the labeled `data class` text and the bare `data object` name through the native members |
   | TypeScript | one conditional chain over the `kind` reads in constructor declaration order; a payload arm narrows to the interface and concatenates the labeled text; a parameterless arm is the name constant |
   | Swift | the immediately-invoked closure form of stdlib spec 12 ruling 6 switching over the associated-value cases; each payload arm binds the labels and concatenates the labeled text |
   | Dart | one conditional chain over the `is` checks of the sealed subclasses in constructor declaration order; a payload arm narrows to the subclass and concatenates the labeled text |
   | Rust | one `match` over the variants; each payload arm binds the fields and writes the labeled text |

   The branch covers every constructor of the enum with no catch-all arm,
   the exhaustiveness the pattern rules of features/01 rule for enum
   subjects. The rendering lives in the operand-form function of each
   target, the function the `Std.string` arm calls (stdlib spec 12
   ruling 4); it renders the same expression in the concatenation and the
   standalone position.
3. The argument forms inside a labeled arm are the operand forms: scalars
   through the conversions of stdlib spec 12 ruling 2, parameterless enum
   arguments through the constructor-name reads, record arguments through
   the member calls of feature spec 31, array arguments through the
   builders of stdlib spec 12 ruling 6, and payload enum arguments
   through the recursive labeled form.
4. In the assembly routine of spec 31 ruling 4, a field whose type is an
   enum renders its operand as `Std.string(<field read>)`; a
   parameterless enum field prints the constructor-name read and a
   payload enum field prints the labeled form. A nullable enum field
   stops the compilation with the named error and the class keeps an
   explicit member.
5. An array element of enum type renders through the same forms (the
   element domain of feature spec 33).
6. Stage 1 renders a payload enum value natively as `Link(target)` with
   the argument and no label; the payload rows assert through the
   `boring_oracle` conditional, and the sample header records the
   divergence, the array-row pattern of stdlib spec 12.

## Samples and tests

- `samples/boring/PrintedEnumOps.hx`:
  `enum PrintedMark { Plain; Ring(diameter:Float); Tag(text:String, weight:Int); }`
  and a `@:dataClass` class `PrintedBadge(mark:PrintedMark,
  width:FloatWidth)`; `markText(mark:PrintedMark)` returns
   `"mark=" + Std.string(mark)` and `markValue(mark)` returns
   `Std.string(mark)`; `badgeText(badge:PrintedBadge)` returns
   `badge.toString()`; `markList(marks:Array<PrintedMark>)` returns
   `Std.string(marks)`.
- `samples/tests/PrintedEnumTests.hx`: `Plain` prints `Plain`;
   `Ring(1.5)` prints `Ring(diameter=1.5)`; `Tag("x", 2)` prints
   `Tag(text=x, weight=2)`; the badge member prints
   `PrintedBadge(mark=Ring(diameter=1.5), width=F64)` in constructor
   parameter order; the parameterless enum field prints the
   constructor-name read; the array row prints
   `[Plain, Ring(diameter=1.5)]`; the payload rows assert through the
   `boring_oracle` conditional on the Haxe target, with the divergence
   recorded in the sample header.
- Both modules are entered in all eight generation hxml files.
- Tree assertions in `tests/ts/printed-enum.test.ts`: the TypeScript tree
  carries the `kind` chain inside the member and at the `markText` site;
  the Swift tree carries the closure switch; the Dart tree carries the
  `is` chain; the Rust tree carries the `match`; the Kotlin tree emits no
  member for `PrintedBadge` and renders the bare operand at the
  `markText` site.
- Mutation checks: `Std.string` over a class instance without the marker
  and over a structure keep the named error; a nullable enum operand
  keeps the named error.
