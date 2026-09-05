# Rust multi-error functions

## Conflict definition

A Rust fallible function has a conflict when its direct throws or reachable call
edges contain payload fault enums from more than one module. A single payload
enum remains unchanged.

## Union synthesis

For a conflicting function, the emitter creates one enum named from the owning
class and function, ending in `Fault` (for example `RunnerLoadFault`). The
function portion uses UpperCamelCase (`through_calls` becomes `ThroughCalls`),
so generated Rust names never contain an underscored function fragment. Each
reachable payload type contributes one variant named `<Payload>Fault`, carrying
an owned instance of that type. A synthetic union is itself one payload type
when it reaches another caller. The function returns `Result<T, RunnerLoadFault>`.
The declaration is emitted in the function's Haxe module and is private to the
generated Rust module boundary through ordinary imports.

Direct `throw` expressions are wrapped at the throw site. Call propagation
uses the complete error type and its module metadata:

- If the caller's reachable error set has one member, its error type is that
  member and the call edge emits only `?`, including when that member is a
  synthetic union.
- If the caller's set has two or more members, the caller gets its own union;
  each member gets one `<Payload>Fault` variant, and a callee union remains a
  union payload. The call edge uses `map_err` into the matching caller variant.

This is value-based and does not use a trait object. The same analysis is
propagated to a fixed point, so a caller of a union function can itself form a
union, including a union as one of its payloads.

## Catch boundary

The existing single-catch region lowering remains the boundary for catch
semantics. A caught payload continues to match its original payload enum. The
multi-catch restriction is unchanged. Single-enum functions retain their
existing emitted shape.

## Worked example

```haxe
enum DiskFault { Missing(path:String); BadHeader; }
enum NetworkFault { Offline; Timeout(seconds:Int); }
class Runner {
  public static function load():String {
    if (useDisk) throw new DiskException(DiskFault.Missing("a"));
    throw new NetworkException(NetworkFault.Timeout(3));
  }
}
```

The relevant Rust shape is:

```rust
pub enum RunnerLoadFault {
    DiskFault(DiskFault),
    NetworkFault(NetworkFault),
}
fn load() -> Result<String, RunnerLoadFault> {
    if use_disk { return Err(RunnerLoadFault::DiskFault(DiskFault::Missing { path: "a".to_string() })); }
    Err(RunnerLoadFault::NetworkFault(NetworkFault::Timeout { seconds: 3 }))
}
```
