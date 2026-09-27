# Errors and standard library contracts

## 1. Error model

Wren stores runtime error and handler state on Fiber. Relevant anchors are runtimeError in [wren_vm.c](https://github.com/wren-lang/wren/blob/99d2f0b8fc2686134b32b18166e037639f7e9f2c/src/vm/wren_vm.c) and caller/error fields in [wren_value.h](https://github.com/wren-lang/wren/blob/99d2f0b8fc2686134b32b18166e037639f7e9f2c/src/vm/wren_value.h). Beep uses Result returns for recoverable errors and removes handler transfer.

Option<T> is None | Some(T). Result<T,E> is Ok(T) | Err(E), where E implements Error. Null does not exist. Neither type exposes unwrap; core types are sealed against user unwrap methods. unwrap_or evaluates its fallback lazily only for None or Err. Matching is always available.

Postfix ? applies only to Result. Ok yields its payload. Err returns from the enclosing Result function after a unique static error conversion or explicit enum injection. Conversion is selected at compile time. Option uses matching/library methods. The language rejects try, try/catch, and try expressions.

panic(message) has type Never. It ends the current host-requested invocation and returns PanicRecord(message, frames). Result cannot catch panic. Panic is for violated program invariants. Input, I/O, and quota failures use Result or host outcomes. Host exceptions are translated by adapters before return. A later invocation may use the VM after panic unless its integrity state is failed.

Ordinary Int overflow, division by zero, Int minimum divided by -1, and invalid shift count produce ArithmeticPanic. Checked methods addChecked, subChecked, mulChecked, divChecked, and shlChecked return Result<Int,ArithmeticError>. Integer division truncates toward zero; remainder has dividend sign. Float follows IEEE 754 binary64 across targets.

## 2. Core interfaces

    interface Display { fn display() -> String }

    interface Eq { fn equals(other: Self) -> Bool }

    interface Hash { fn hash() -> Int }

    interface Error {
      static code: String
      fn display() -> String
    }

    interface Sequence {
      type Element
      fn iterator() -> Iterator<Element>
    }

    interface Iterator<T> { fn next() -> Option<T> }

A Map key implements Eq and Hash. Equal values must hash equally. Equality is reflexive, symmetric, and transitive. Hash is stable during one VM execution and need not persist across releases. Error.code is stable within one release; display text is for people and is not serialized.

Sequence.Element participates in generic inference. Array<T> implements Sequence with Element=T. Range uses Int. String iteration yields one Unicode scalar per step, represented by Int code point in the initial library. Iterator exhaustion is permanent: after None, every later next returns None.

## 3. Collections

Array<T> stores only T. get(index: Int) -> Option<T>. set(index: Int, value: T) -> Result<Unit,BoundsError>. Map<K,V> requires K: Eq + Hash. get/remove return Option<V>; insert returns prior Option<V>. Iteration yields every entry once; order is unspecified unless an ordered map type declares otherwise.

Empty literals require expected collection type or explicit type arguments. Heterogeneous elements require explicit conversion to a declared common type. Program bounds/input errors use Option or Result; unrecoverable allocator/integrity limits use host ResourceLimit.

## 4. Strings and numeric conversions

String is immutable Unicode scalar sequence. Indexing, slicing, iteration and equality use scalar values. UTF-8 byte access is explicit. Invalid host byte decoding returns Result. Interpolation calls Display once per expression, left to right.

Byte to Int is exact. Int to Byte returns Result<Byte,RangeError> unless the source is a fitting compile-time literal. Int to Float and Float to Int use named conversions with documented rounding and range checks. No implicit numeric widening occurs.

## 5. Host capability errors

File, network, clock, random, and process operations are absent until a host registers a capability module. Operations return typed Result. Missing registration fails binding before initialization. Host errors map to declared Error constructors. Adapters catch host exceptions and translate them before ABI return.

## 6. Required tests

- Option/Result exhaustive cases; Err identity through ?.
- unwrap rejection and lazy, typed unwrap_or.
- try/try-catch rejection.
- Err propagation does not call panic callback.
- panic produces separate PanicRecord and ordered frames.
- Checked arithmetic returns ArithmeticError; ordinary invalid arithmetic panics.
- Eq/Hash law tests for core key types.
- Iterator permanently returns None after exhaustion.
- Unicode scalar indexing matches across UTF-8/UTF-16 targets.
- Missing capability fails binding; host error maps to declared error.
