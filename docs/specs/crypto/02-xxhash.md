# Crypto spec 02: XXH64 and XXH3-128

## API and streaming contract

`Xxh64.make(data, seed)` is the one-shot form. `new Xxh64(seed)` followed by
any number of `update` calls and `digest()` is equivalent to one-shot hashing
the concatenation of the updates. An empty update is permitted. `digest()` is
idempotent: it does not consume buffered bytes or alter the accumulator, and a
later `update` continues the same stream.

The `Xxh128.make(data, seed)` API is one-shot and returns `{high, low}` in the
same order as `XXH128_hash_t`'s high and low words. Its result is defined for
all byte lengths and for both zero and non-zero seeds.

## XXH3-128 branch structure

The implementation retains all reference branches:

- length 0;
- lengths 1 through 16;
- lengths 17 through 128;
- lengths 129 through 240;
- lengths greater than 240, using stripe accumulation, final stripe
  accumulation, and accumulator scrambling before merging into 128 bits.

The short branches use the secret offsets and mix the first, last, and middle
bytes exactly as specified by XXH3. Long inputs process 64-byte stripes with
the 192-byte default secret, scramble each accumulator with the secret, and
merge the accumulators with 64-by-64-to-128 multiplication.

For a non-zero seed, `XXH3_initSecret` derives a private secret by adding the
seed to one 64-bit half and subtracting it from the other half of every
secret word pair, with the reference avalanche/mixing operation applied at
each four-byte derivation position. Seed zero uses the default secret.

## 128-bit multiplication

Haxe `Int64` has no portable 128-bit product. The portable decomposition treats
each operand as a high and a low unsigned 32-bit part:

```haxe
static function carryOut(a:haxe.Int64, b:haxe.Int64, sum:haxe.Int64):haxe.Int64 {
	return (((a & b) | ((a | b) & ~sum)) < 0)
		? haxe.Int64.make(0, 1) : haxe.Int64.make(0, 0);
}

static function wideMul(a:haxe.Int64, b:haxe.Int64):{hi:haxe.Int64, lo:haxe.Int64} {
	final aLo = haxe.Int64.make(0, haxe.Int64.getLow(a));
	final aHi = haxe.Int64.make(0, haxe.Int64.getHigh(a));
	final bLo = haxe.Int64.make(0, haxe.Int64.getLow(b));
	final bHi = haxe.Int64.make(0, haxe.Int64.getHigh(b));
	final p00 = aLo * bLo;
	final p01 = aLo * bHi;
	final p10 = aHi * bLo;
	final p11 = aHi * bHi;
	final t = p01 + p10;
	final carry = carryOut(p01, p10, t);
	final tShl = t << 32;
	final lo = p00 + tShl;
	final carry2 = carryOut(p00, tShl, lo);
	final hi = p11 + (t >>> 32) + (carry << 32) + carry2;
	return {hi: hi, lo: lo};
}
```

The carry test reads the sign bit. `sum < a` cannot be used here because Haxe
comparisons are signed while the operands represent unsigned bit patterns.

## Boundaries and representation

XXH64 buffering uses signed Haxe `Int` comparisons for sentinel expressions
such as `p <= mem.length - 8`; a negative right-hand side must prevent the
loop. The implementation must not reinterpret that expression as an unsigned
comparison because a Rust business module stores `Int` as `u32`.

`StringTools.hex` is an unsigned view of the low bits. A negative 32-bit word
is rendered with eight hexadecimal digits, and a 64-bit result is rendered as
its high word followed by its low word. Target-specific views are: TypeScript
uses `>>> 0`, Kotlin uses `.toUInt()`, Swift uses
`UInt32(bitPattern:)`, Dart uses `.toUnsigned(32)`, and Rust uses its native
wrapping bit representation.

## Vectors and source

The XXH3-128 vectors are taken from the official xxHash repository's
`XXH3_128bits_withSeed` implementation and independently checked against
`hash-wasm`. Boundary vectors include empty, 1, 16, 17, 128, 129, 240, 241,
1003, and 1004-byte inputs, with zero and non-zero seeds.
