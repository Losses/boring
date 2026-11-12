# Release note: Rust target instance methods become associated functions (UFCS call)

## ABI change

boring's Rust target now generates a plain class's instance methods as associated
functions, with the receiver as the first explicit parameter:

```rust
pub(crate) fn method_name(this: &Rc<RefCell<Self>>, ...) -> T
```

(`pub`/`pub(crate)` follows class visibility; the shape above is the measured
generated form.)

Any downstream hand-written Rust code that calls a boring generated class's
instance method with method syntax must migrate to UFCS. The old form no longer
compiles in Rust and reports `E0599 no method found for struct RefMut`.

## Migration rule

For a handle `h: Rc<RefCell<T>>`:

```rust
// Old (no longer compiles)
h.borrow_mut().m(args);   // mutating method
h.borrow().m(args);       // read-only method

// New (UFCS): pass the handle reference as the first argument
T::m(&h, args);
```

Note the first argument is `&h`: the generated signature receives `&Rc<RefCell<Self>>`.

## Examples (boring's own tests/rust/vector_gen.rs and vector_gen_f32.rs are migrated)

```rust
// BinaryReader
reader.borrow_mut().read_u16()  ->  BinaryReader::read_u16(&reader)
reader.borrow_mut().read_u32()  ->  BinaryReader::read_u32(&reader)
reader.borrow().remaining()     ->  BinaryReader::remaining(&reader)

// BufferHolder
holder.borrow_mut().write_byte(0xAB) -> BufferHolder::write_byte(&holder, 0xAB)
holder.borrow_mut().finish()         -> BufferHolder::finish(&holder)
```

## Unaffected

- `@:dataClass` and other value types still generate by value/borrow.
- Opaque handle parameters (for example callback receivers) are outside this migration.
- Callers generated for kotlin/ts/dart/swift need no change (they already emit per-target syntax).

## Version and rollback

- This is a breaking ABI change and is handled as a breaking upgrade (current release line 1.4.0).
- The direction is the Astra-ruled B6 handle ABI; it does not roll back.
- Downstream code that is not migrated fails with `E0599`, which is expected; migrate per the rule above.
