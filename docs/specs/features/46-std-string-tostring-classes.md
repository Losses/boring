# Feature spec 46: `Std.string` for ordinary classes with `toString`

## Scope

`Std.string` accepts ordinary class instances when the class declares or
inherits an instance member named `toString`. This extends the existing
scalar, enum, record, and supported collection set, including collection
members whose element type is such a class.

## Ruling

1. Each target follows the typed class table: a `TInst` class is accepted when
   its instance fields resolve `toString` locally or through its superclass.
   The emitted operation is the same class operation used for records:
   `value.toString()` (or the target's equivalent spelling).
2. The class guard is after Array, SortedSet, SortedMap, type parameter, and
   record arms. Consequently those existing types, `String`, ReadOnlyArray,
   and enums retain their established lowering.
3. A class without a declared or inherited `toString` remains rejected with
   `Std.string accepts scalars, enum values, records, and arrays of them only`.
   The compiler does not guess a textual representation at runtime.

## Worked example

```haxe
class Point {
    public function toString():String return "point";
}

class Example {
    public static function text(point:Point, points:Array<Point>):String {
        return Std.string(point) + ":" + Std.string(points);
    }
}
```

The target-specific class operation has the following shape:

- TypeScript: `point.toString()` and an array loop containing
  `points[i].toString()`.
- Kotlin: `point.toString()` and an array loop containing
  `points[i].toString()`.
- Swift: `point.toString()` and an array loop containing
  `points[i].toString()`.
- Dart: `point.toString()` and an array loop containing
  `points[i].toString()`.
- Rust: `point.to_string()` and an array loop containing
  `points[i].to_string()`.
