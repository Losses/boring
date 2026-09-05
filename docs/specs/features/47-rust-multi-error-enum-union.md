# Rust multi-error functions

## Conflict definition

A Rust fallible function has a conflict when its direct throws or reachable call
edges contain payload fault enums from more than one module. A single payload
enum remains unchanged.

## Union synthesis

For a conflicting function, the emitter creates one enum named from the owning
class and function, ending in `Fault` (for example `RunnerLoadFault`). Each
reachable payload enum contributes one variant named `<Payload>Fault`, carrying
an owned instance of that enum. The function returns `Result<T, RunnerLoadFault>`.
The declaration is emitted in the function's Haxe module and is private to the
generated Rust module boundary through ordinary imports.

Direct `throw` expressions are wrapped at the throw site. A call edge whose
callee error type differs from the caller's union is wrapped with
`map_err(|e| RunnerLoadFault::<Payload>Fault(e))`. This is value-based and does
not use a trait object.

The same analysis is propagated to a fixed point. Therefore a caller of a union
function can itself form a union, including a union as one of its payloads.

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
