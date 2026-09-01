# Standard library spec 14: numeric parsing and NaN

## Scope

This specification rules `Std.parseFloat`, `Std.parseInt`, and
`Math.isNaN` on all five source targets (ts, kotlin, swift, dart, rust).
The shared domain includes callers that pass a `String` to either parser and
callers that test the resulting `Float` with `Math.isNaN`. A caller may
observe a parser's failure result and may branch on it; parsing is not
restricted to literals or to strings known to be valid. `Math.isNaN` is in the
shared domain only for a `Float` operand. An `Int` or a nullable integer
result from `Std.parseInt` is not a valid operand for it.

## Contract

`Std.parseFloat(s)` trims leading and trailing exactly these six characters: space,
`\t`, `\n`, `\v` (U+000B), `\f` (U+000C), and `\r`, and parses the whole
remaining token. No other character is trimmed, including non-ASCII whitespace
and the other control characters. The accepted grammar is:

```
float  := sign? (digits ("." digits?)? | "." digits) exponent?
exponent := ("e" | "E") sign? digits
sign := "+" | "-"
digits := [0-9]+
```

The token must contain at least one digit, and an exponent must contain at
least one digit. Thus `1`, `-1.25`, `+1.`, `.5`, `1e3`, and `-1.25E+2`
are valid. Hexadecimal prefixes, `Infinity`, `NaN`, and whitespace outside the
six-character set above are not part of this grammar. Empty, whitespace-only, malformed, and partial
tokens such as `12x`, `0x10`, `1e`, and `+.` fail. A valid token whose
magnitude exceeds the target floating-point range follows the target's IEEE
conversion, including infinity; it is not a syntax failure.

`Std.parseInt(s)` trims the same six characters and parses the whole remaining
token as a signed base-10 integer. Its decimal grammar is:

```
integer := sign? digits
```

A hexadecimal form is also accepted only when the trimmed token begins with
an optional sign followed immediately by `0x` or `0X` and then one or more
hexadecimal digits:

```
hexInteger := sign? ("0x" | "0X") hexDigits
hexDigits := [0-9a-fA-F]+
```

The prefix is part of the token; it does not request decimal-prefix parsing.
`12x`, `0x10z`, `0x`, `--1`, a decimal point, an exponent, and an empty or
whitespace-only token fail. A value outside the Haxe `Int` range also fails;
decimal and hexadecimal values are uniformly converted through a 64-bit integer
before the Haxe `Int` bounds are checked. In particular, `-0x80000000` is valid
and produces `-2147483648`; there is no truncation or wrapping. On success the
result is an `Int`; on
failure the Haxe return value is `Null<Int>` and is `null`.

`Std.parseFloat` returns a `Float`, using `Math.NaN` as its exact failure
result. `Math.isNaN(x)` returns true exactly when the `Float` is an IEEE NaN,
and false for finite values and infinities. It does not perform conversion and
it does not treat a failed integer parse as a NaN. These failure results are
part of the shared contract; target-specific exception behavior does not
alter them. Parser callers inside the domain must be able to distinguish
failure without a thrown exception.

## Current translations

| Target | State |
| --- | --- |
| TypeScript | The registry work names `Number.parseFloat`, `Number.parseInt`, and `Number.isNaN`, but no complete-token standard-library lowering is yet authoritative. Native parsing must be guarded because it accepts partial forms. |
| Kotlin | No cross-target numeric reader is specified yet. The target's nullable parse functions provide the needed non-throwing failure channel once grammar validation is added. |
| Swift | No cross-target numeric reader is specified yet. The target's failable initializers provide the needed non-throwing failure channel once grammar validation is added. |
| Dart | No cross-target numeric reader is specified yet. The target's `tryParse` functions provide the needed non-throwing failure channel once grammar validation is added. |
| Rust | No cross-target numeric reader is specified yet. `parse` provides a non-panicking error channel, but its accepted grammar and result type must be constrained to this contract. |

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Validate the complete token, then use one native numeric conversion | One scan plus the target conversion; no exception is used for an expected miss. | The grammar and failure result are explicit and identical on every target. | The validator is the one shared-domain boundary; native arithmetic remains native. | The call site shows parsing while the contract explains the guard. |
| Call each target's permissive parser directly | Often one call. | Partial tokens, prefixes, whitespace, and overflow differ by target. | Every caller would need its own post-checks. | A short expression hides incompatible failure behavior. |
| Construct a regular expression inline at each call site | Rejected: Kotlin's `Pattern.compile` has no process-wide cache, so every call recompiles the pattern. | No ambiguity benefit. | Duplicates validation work. | Hides the performance cost. |
| Throw on invalid input | No nullable result allocation on some targets. | Expected invalid input becomes exception control flow. | Callers duplicate recovery logic and lose the Haxe result type. | It contradicts `Null<Int>` and the NaN failure contract. |

## Ruling

1. Both parsers perform the Contract grammar check before conversion and
   accept only a complete trimmed token. The check rejects any unconsumed
   character, including a valid-looking prefix followed by invalid text.
   It also rejects integer overflow before a target conversion can wrap. The
implementation may use a shared lexical helper, but callers observe the
exact Haxe results above.

2. `Std.parseFloat(s)` renders as a non-throwing native conversion after that
   check:

   | Target | Rendering |
   | --- | --- |
   | TypeScript | `Number.parseFloat(s)` with the complete-token validation result guarding the call; failure is `Number.NaN`. |
   | Kotlin | Calls the emitted `std.NumberParsing` shim (validation patterns are constructed once at program startup). |
   | Swift | Calls the emitted `std.NumberParsing` shim (validation patterns are constructed once at program startup). |
   | Dart | Calls the emitted `std.NumberParsing` shim (validation patterns are constructed once at program startup). |
   | Rust | `s.parse::<f64>().unwrap_or(f64::NAN)` |

   The fallback is observable as the required NaN only for a failed parse;
   valid calls do not use it. The f32 configurations retain the Haxe Float
   precision rule after parsing and still use the same NaN test.

3. `Std.parseInt(s)` preserves its Haxe `Null<Int>` result and does not
   manufacture a numeric sentinel:

   | Target | Rendering |
   | --- | --- |
   | TypeScript | validated decimal or hex form through `Number.parseInt(s, 10)` or the explicitly validated hex form; failure is `null`. |
   | Kotlin | Calls the emitted `std.NumberParsing` shim (validation patterns are constructed once at program startup). |
   | Swift | Calls the emitted `std.NumberParsing` shim (validation patterns are constructed once at program startup). |
   | Dart | Calls the emitted `std.NumberParsing` shim (validation patterns are constructed once at program startup). |
   | Rust | validated decimal form through `s.parse::<i32>()`, or validated hex digits through `i32::from_str_radix(digits, 16)`; failure is `None` in `Option<i32>` |

   The nullable forms are the complete-domain rule: no caller in the shared
   domain observes a fabricated zero, a wrapped integer, or a thrown parse
   exception. Rust uses `Option<i32>` because `Null<Int>` has no integer
   sentinel representation. Hex input is passed to a radix-16 conversion
   only after the validator has established the exact prefix and digits.

4. `Math.isNaN(x)` is a predicate over a `Float` and renders as follows:

   | Target | Rendering |
   | --- | --- |
   | TypeScript | `Number.isNaN(x)` |
   | Kotlin | `x.isNaN()` for `Double`, or `kotlin.math.isNaN(x)` where the generated numeric type requires the function form |
   | Swift | `x.isNaN` |
   | Dart | `x.isNaN` |
   | Rust | `x.is_nan()` |

5. No parser throws for an invalid token in the shared domain. The only
   failure values are `NaN` for `Std.parseFloat` and `null`/`Option.none`
   for `Std.parseInt`; `Math.isNaN` never changes either value. Tests must
   include successful, failed, and partial tokens on every target.

## Samples and tests

- `samples/boring/NumberParsingOps.hx` exercises signed integers, decimal
  fractions, leading and trailing ASCII whitespace, exponents, the `0x`
  and `0X` integer forms, overflow, empty input, invalid input, and partial
  tokens. It checks float failures with `Math.isNaN` and integer failures
  with an explicit null check.
- `samples/tests/NumberParsingTests.hx` enters the same cases for ts, kotlin,
  swift, dart, and rust, including f32 configurations where applicable.
- Tree assertions verify the five renderings in this ruling, nullable integer
  results, NaN fallbacks, and validation before native conversion. They reject
  direct permissive parsing that can accept a partial token.
- The cross-target consistency run compares both success values and failure
  classifications; it separately checks that `parseInt` failure is nullable
  and that `parseFloat` failure satisfies `Math.isNaN`.

## Test hooks

The numeric reader hook owns the grammar validator and records whether the
entire trimmed token was consumed. Target-specific hooks assert the native
conversion spelling and its fallback, while the shared hook asserts the Haxe
result type. A negative test passes `12x`, `1e`, `0x`, and overflow values
through each parser and confirms no target throws or returns a partial value.
