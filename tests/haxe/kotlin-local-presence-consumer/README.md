# Kotlin local presence production fixture

Run the focused evidence procedure from the repository root:

```sh
bash tests/haxe/kotlin-local-presence-consumer/run-focused.sh
```

It retains each command, numeric status, stdout, stderr, the Kotlin jar, and
the input hashes before and after the run under
`out/kotlin-local-presence-consumer/attempt-*`. The equivalent commands are:

```sh
nix develop -c haxe tests/haxe/kotlin-local-presence-consumer/kotlin-gen.hxml
nix develop -c bun tests/haxe/kotlin-local-presence-consumer/check-output.ts
nix develop -c bun tests/haxe/kotlin-local-presence-consumer/check-output.ts --negative-control
nix develop -c bash -c 'kotlinc $(find out/kotlin-local-presence-consumer/kotlin-gen/kotlinlocalpresence -name "*.kt") tests/haxe/kotlin-local-presence-consumer/LocalPresenceRunner.kt -include-runtime -d out/kotlin-local-presence-consumer/local-presence.jar && java -cp out/kotlin-local-presence-consumer/local-presence.jar kotlinlocalpresence.LocalPresenceRunnerKt'
```

The HXML sends the authored Haxe modules through the production Kotlin compiler
into `out/kotlin-local-presence-consumer/kotlin-gen`. `check-output.ts`
compares that tree with fixed expectations that are separate from the
generated Kotlin. `LocalPresenceRunner.kt` compiles and executes the emitted
methods. Its successful output is `KOTLIN LOCAL PRESENCE PASS`.
The output checker asserts 28 generated-output and source-fact cases. The
negative-control command verifies direct reads and rejects temporary safe-call
mutations of both guarded operations.

The negative-control command mutates the emitted `presentLocal` and
`nestedLiteral` operations in a temporary copy from direct access to safe
calls plus extraction. It records the expected and observed decision for each
original and mutation. The temporary copy does not alter generated output.

## Cases and source observations

| Haxe input | Source fact expectation | Target storage and Kotlin assertion | JVM evidence |
| --- | --- | --- | --- |
| `LocalPresenceOps.presentLocal`: parameter `local` is read after `local != null` | Macro output records both the guard read (`Unknown`) and guarded read (`Present`) | Non-null branch read emits `local.read("present")` without `?.` or `!!` | Present and absent calls are asserted |
| `LocalPresenceOps.absentLocal`: `local:Null<String> = null` | Macro observes `LocalUse / Available / Transferred / Absent` | `String?` declaration and plain return | Null return is asserted |
| `LocalPresenceOps.unknownOptional`: local copies nullable parameter | Macro observes `LocalUse / Available / Transferred / Unknown` | `LocalPresenceOps?` declaration and return | Identity-preserving non-null input is asserted |
| `LocalPresenceOps.unknownRequired`: `cast(value, LocalPresenceOps)` initializes `LocalPresenceOps` local | Macro observes the return read as `LocalUse / Available / Transferred / Unknown` | Declared return/local type is `LocalPresenceOps`; current emitter outputs `value!!` | Non-null input is asserted; null extraction is not invoked |
| `producedConstruction`, `producedCall`, `producedField` | Construction, call result, and field projection are separate nonlocal input forms | Function-scoped snippets assert `LocalPresenceOps(null)`, `uppercase()`, and `.label` | All three are asserted |
| `ordinaryReturn` versus `RequiredTextRenderer.render` | Nullable receiver result | Ordinary declaration is `String?` with `?.read`; override stays `String` and emits `?.read(...)!!` | Both non-null receiver paths are asserted |
| `nestedLiteral`, `staticEntry`, the `new(value)` constructor, and `constructorEntry` | The nested guarded read has a `Present` occurrence in its own body and `NoOccurrence` in the outer body | Function and constructor sections are checked separately; nested output contains `value.read("nested")` | Null and non-null nested/static paths run; `LocalPresenceOps(ops)` enters the actual Haxe constructor |
| `fusionLoopTrailing` | The production prepared root, after expansion and fusion, records the trailing local read as `Present` occurrence 3 | Generated output retains the trailing `val result = local` read | Not invoked by this runner |
| `defaultedNullable` | The source parameter read remains `Unknown` in the prepared root | The signature lifts the default to `value: String = "ready"`; the body calls `value.uppercase()` directly through target entry storage | Default and explicit values are asserted |
| `unprovenNullableUppercase` | The parameter read remains `Unknown` and target entry is false | The `String?` receiver uses `value?.uppercase()` and returns `String?` | Null returns null; non-null input becomes uppercase |
| `nestedNameRestore` | Nested names belong to the literal scope | Inner and outer `after` declarations retain their names, including the outer declaration printed after the literal | `innerouter` is asserted |
| `LocalPresenceEnumOps.firstPayloadMember` / `secondPayloadMember` reuse `choice` and narrow the same payload enum | The read occurs in each narrowed enum arm | Each member is checked for its own `choice.value` output | Both outputs are invoked |

`LocalPresenceFactProbe.hx` queries `SourceLocalPresenceAnalysis` on the typed bodies of the
local and nested cases and writes `source-facts.tsv`; `check-output.ts` checks
those observations. It also queries a local node absent from its prepared body
and a nonlocal node on an unreachable path. The nested probe checks a read
against its inner and outer body facts. The fusion/loop/trailing probe checks
that its trailing local read has an occurrence. The frozen source analysis
keeps its separate 167-row test. The payload-enum methods run against candidate bytes;
the original cross-member defect has not been regenerated from baseline bytes.

The generation define records `prepared-root-facts.tsv` from the exact root
passed to the Kotlin emitter after expansion and fusion. The consumer query
records `production-use-facts.tsv`. The checker requires the nested `Present`
occurrence in both files. It requires the trailing local `Present` occurrence
in the prepared root and the corresponding emitted trailing read. The target
does not query presence for that trailing assignment, so no consumer-use row
is expected for occurrence 3. The defaulted parameter assertion requires
`Unknown` in the prepared source facts and a true target entry query before
checking the non-null signature and direct body read.

## Output and known limits

The generated excerpts are in
`out/kotlin-local-presence-consumer/kotlin-gen/kotlinlocalpresence/`. The
fixture compiles and runs that tree with the handwritten runner. It covers
present, absent, and unknown local source expectations; optional and required
target storage; ordinary and interface return shapes; nested, static, and
constructor bodies; construction, call, and field results; and same-name enum
payload-enum members. The source adapter reports a local `NoOccurrence` query
and a nonlocal unreachable query. The prepared-root trace proves source
occurrence identity after the production expanders and declaration fusion.
The target's later loop and trailing-block formatting does not rewrite that
prepared root; the emitted trailing read is checked separately.
