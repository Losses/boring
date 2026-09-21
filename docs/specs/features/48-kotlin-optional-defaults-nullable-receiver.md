# Feature spec 48: Kotlin optional defaults and nullable receivers

## Scope

This feature covers Kotlin lowering for Haxe optional parameters and member calls
whose receiver has the static type `Null<T>`. It applies to ordinary methods,
constructors, interfaces, and extracted functions emitted by the Kotlin target.

## Ruling

1. A registered Haxe optional parameter is emitted with a Kotlin default value.
   The generated parameter keeps `T?` when the Haxe default is `null`, for
   example `optBody: ProbeBody? = null`. A non-null default uses the existing
   default-expression lowering and may remove the `Null<T>` wrapper when the
   expression cannot produce null. Literal defaults, enum values, and supported
   coalescing expressions use the same lowering as existing Kotlin defaults.
2. Interface declarations may carry defaults, but an implementation method that
   overrides an interface method does not repeat the default. Kotlin rejects a
   default value on an overriding declaration; calls through the interface use
   the interface default.
3. Omitted arguments are still completed by the typed Haxe expansion pass where
   the target requires a concrete argument. Kotlin declarations retain native
   defaults, so no new call-site naming scheme is required. Existing calls do
   not omit an intermediate argument in a way that requires Kotlin named
   arguments; the current positional call shape is therefore unchanged.
   The expanded argument keeps the parameter's position: a call whose argument
   list is shorter than the callee's parameter list renders only the arguments
   it is given and leaves the tail to the Kotlin defaults, while a call that
   Haxe completed with an explicit null for an omitted intermediate slot keeps
   that slot at its position.
3a. A registered coalescing default whose expression reads an earlier parameter
   of its own function is written for the callee body, where that parameter is a
   binding. Its text therefore cannot be materialized at a call site. Two shapes
   are distinguished at the call site: the omitted trailing tail renders no
   argument and the Kotlin default supplies the value in the callee scope, and
   an explicit null at the slot renders each parameter read of the default
   against the argument this call passes for that parameter, so
   `pick(a, b = a)` called as `pick("alpha", null)` renders
   `pick("alpha", "alpha")`. A read of a parameter the call itself omits
   resolves to `null` where the rendered parameter keeps its nullable type and
   otherwise renders that parameter's own default expression. Without this
   resolution the call site emits the bare parameter name, which names no
   binding outside the callee and breaks the argument-to-parameter
   correspondence.
4. For an instance member call, the Kotlin target inspects the compile-time type
   of the receiver. The `Null<T>` case emits `?.`; non-nullable receivers emit `.`.
   The decision uses only the compile-time type table.
5. At a call site, a null literal for a parameter with a registered default
   materializes that default. A nullable argument lowers as Kotlin's
   null-coalescing expression over the default, preserving Haxe normalization
   for both literal and variable arguments. Other nullable receiver behavior
   remains as described below; a nullable member result flows into existing
   assignment or assertion handling.

## Worked example

Haxe source:

```haxe
class ProbeBody {
    public function label():String {
        return "present";
    }
}

class NullProbe {
    public function new(?optBody:ProbeBody, ?label:String = "fallback") {}

    public static function read(body:Null<ProbeBody>):Null<String> {
        return body.label();
    }
}
```

Generated Kotlin shape:

```kotlin
class NullProbe(optBody: ProbeBody? = null, label: String = "fallback")

fun read(body: ProbeBody?): String? {
    return body?.label()
}
```

The nullable parameter keeps `?` for the null default, while the member call
uses `?.` because the receiver's static Haxe type is `Null<ProbeBody>`.
