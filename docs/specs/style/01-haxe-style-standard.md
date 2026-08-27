# Style spec 01: Haxe style standard and generation interception

## Scope

This specification defines the Haxe-level language style standard for code accepted by the translation pipeline, and the interception that enforces it. The interception runs before generation on every pipeline entry, rejects non-conforming code and unsupported features with a named violation at the offending site, and aborts the run. Haxe source inside the pipeline keeps the friendly source syntax of the language; every restriction below exists because the corresponding construct either has no translation with identical observable behavior on Rust, TypeScript, and Kotlin, or its translated form has uncontrollable cost on the JavaScript target.

The standard binds `haxe/src` and any source the generator later consumes. The Haxe test tree `tests/haxe` compiles through the same interception.

## Style standard

Conforming source looks like the codec that already exists in the repository. The standard is stated as positive rules first; the rejection table below names every construct that fails interception.

1. **Declarations carry explicit types.** Public functions declare parameter and return types. Structure typedefs declare every field with a type and a `final` or mutable marker. Locals use `final` unless reassigned.
2. **Arrays iterate by index range.** `for (i in 0...array.length)` with `array[i]` access is the only array iteration form, per `docs/specs/features/09-iterators.md`. Collections are arrays: `haxe.ds.Map` and its implementations have no translation with fixed cross-language behavior, and a keyed-lookup need appears as a specification amendment naming the structure and its per-platform shape.
3. **Static objects use their source syntax.** Dot access reads fields, bracket access with an `Int` indexes arrays, brace literals construct, per `docs/specs/features/16-static-object-access.md`.
4. **Failures are enum-carrying exceptions.** Every `throw` constructs a `haxe.Exception` subclass that carries a Haxe enum instance naming the variant, per `docs/specs/features/06-errors-and-results.md`. Catch clauses name the exception type; a `Dynamic` catch accepts every value and identifies nothing.
5. **Control flow stays flat.** `if`, `switch`, `while`, `do`/`while`, range `for`, `break`, `continue`, and early `return` are the only control-flow forms; jumps through function values, exceptions as non-error jumps, and data-driven dispatch tables are rejected. Enum switches are exhaustive with no catch-all. Each target renders the platform construct ruled in `docs/specs/features/15-control-flow.md`; observable behavior is identical and statement-level correspondence is not a requirement.
6. **Numbers use the platform tower.** `Int` and `Float` carry all codec arithmetic; `haxe.Int64` appears only in the cases `docs/specs/stdlib/05-haxe-int64.md` permits.
7. **Data has no inheritance.** Record types are structure typedefs or classes with fields; polymorphism goes through generics, per `docs/specs/features/05-generics.md`.

A canonical conforming function:

```haxe
public static function decode(bytes:Bytes):Array<GlyphMetrics> {
	final reader:BinaryReader = new BinaryReader(bytes);
	final count:Int = reader.readU32();
	final records:Array<GlyphMetrics> = new Array<GlyphMetrics>();
	for (index in 0...count) {
		final codePoint:Int = reader.readU32();
		final advanceEm:Float = reader.readF64();
		records[index] = {
			codePoint: codePoint,
			advanceEm: advanceEm,
			bounds: readBounds(reader),
		};
	}
	if (reader.remaining() != 0) {
		throw new VectorException(TrailingBytes(reader.remaining()));
	}
	return records;
}
```

## Rejection table

Every row names a violation, states the construct that triggers it, and gives the detection point on the untyped tree or the typed tree. Every violation is fatal: the interception reports the first occurrence it reaches with the violation name, file, and line, and aborts before generation.

| Violation | Construct | Detection point |
| --- | --- | --- |
| `V01 IteratorLoop` | `for (item in subject)` where the subject is not an integer range expression | untyped `EFor` whose iteration subject is not an `EBinop(OpInterval, _, _)` expression |
| `V02 FunctionalIteration` | `Lambda` module calls, array methods taking function values (`map`, `filter`, `fold`, and the rest listed in `docs/specs/features/09-iterators.md`), and comparator `sort`; sorting goes through the named strategies of `docs/specs/features/17-sorting.md` | untyped `ECall` whose callee field is one of the listed method names, or `sort` with an argument |
| `V03 Reflection` | `Reflect` and `Type` module calls, `Type.getClass`, `Type.enumParameters` | untyped `ECall` whose callee is a field of the root modules `Reflect` and `Type` |
| `V04 UntypedThrow` | `throw` of any value that is not an instance of an enum-carrying `haxe.Exception` subclass: raw strings, enum values without the wrapper, bare `haxe.Exception` constructed from a message | `TThrow` whose expression type is not a subclass of the domain exception base |
| `V05 DynamicValue` | Any expression typed `Dynamic`, any `cast` without a target type, `untyped` blocks | untyped `ECast` without a target type and any `EUntyped`; `TDynamic` in the inferred type of a checked expression |
| `V06 StringKeyedAccess` | Bracket access with a `String` key on a structure | `TArray(e1, e2)` where `e2` has string type and `e1` has an anonymous structure type |
| `V07 ShapeMutation` | Assignment to a field no structure type declares; any operation adding or removing fields | `TBinop(OpAssign)` whose target field is absent from the subject's type |
| `V08 LoopBodyClosure` | Function value or arrow function appearing inside a loop body | `TFunction` nested within a `TFor` or `TWhile` body |
| `V09 RecursiveFormatType` | Format definition whose record types form a cycle | Schema validation on the `FormatDef`, per `docs/specs/binary/04-key-index-retrieval.md` |
| `V10 StrideViolation` | Variable-width field, or nested runtime-count array, in an accessor-eligible format | Schema validation on the `FormatDef`, per `docs/specs/binary/04-key-index-retrieval.md` |
| `V11 Int64Misuse` | `haxe.Int64` outside the permitted cases of the bigint use-case standard | Type reference to `haxe.Int64` outside the modules `docs/specs/stdlib/05-haxe-int64.md` lists |
| `V12 DataInheritance` | A guarded class extends a class other than through the `haxe.Exception` chain that rule 4 sanctions | Class declaration with a superclass outside the exception chain |
| `V13 HashMapCollection` | `haxe.ds.Map` and its implementations (`StringMap`, `IntMap`, `ObjectMap`, `HashMap`) | Type reference resolving to the named modules |
| `V14 DynamicCatch` | `catch (error:Dynamic)` | `TTry` catch variable typed `Dynamic` |
| `V15 EnumDefaultArm` | A `switch` over an enum with a `default` arm | `TSwitch` whose subject the compiler wrapped in `TEnumIndex` or typed as an enum, with a non-null default expression |

The violation set grows with the specification set: adding a restriction to any feature or binary specification adds a row here in the same change, so the interception and the rules stay in one commit.

## Interception mechanics

The interception is a Haxe macro in two passes:

1. Every pipeline entry that compiles or generates from `haxe/src` registers the interception macro, including the test compile in `tests/haxe/compile.hxml`.
2. Pass 1 runs as a `@:build` macro over the untyped field expressions of every class, injected with `Compiler.addGlobalMetadata` and guarded by the source paths. The typer rewrites `for (item in array)` into a counter loop, expands `array.map(fn)` into an inlined loop holding the function value, and inlines `Reflect.hasField` into a prototype call; the untyped tree is the only layer where those source constructs survive, so `V01` through `V03` and the source-level `V05` forms check there.
3. Pass 2 runs after the compiler types all modules and walks every typed expression of every guarded class; the remaining rows check there.
4. Each walk step tests the rejection table above against the current node; the first hit calls `Context.fatalError` with the violation name, the file, and the line of the offending node, which aborts compilation. The error message format is `Vnn Name: message`, so test assertions match on the violation name.
5. The interception performs no repair and no fallback. A rejection means the source changes or the specification that rejects it changes; nothing in between.

The repository owns no generator yet; until one exists, the interception is the enforceable part of this specification and guards the Haxe tree against drifting into shapes the other trees cannot mirror.

## Test hooks

- One test per rejection row: `tests/interception/cases/<name>/Case.hx` holds a minimal fragment whose first line names the expected violation (`// expect: V01 IteratorLoop`). `bun run test:intercept` compiles each case with the interception guarding that case directory and asserts the abort names the expected violation. `V07 ShapeMutation` has no fragment: the compiler rejects writes to final fields before either pass, so its row is defense in depth. Run under the flake shell, exactly like `test:haxe`.
- One positive test: `bun run test:haxe` compiles `haxe/src` and `tests/haxe` with the interception registered and reports zero violations; the same command runs the Haxe test suite.
