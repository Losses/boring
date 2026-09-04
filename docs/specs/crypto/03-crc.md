# Crypto spec 03: CRC

## Parameter model

`CrcModel(width, poly, init, refin, refout, xorout)` holds the standard
width-bit CRC parameters. The portable API is:

```haxe
Crc.hash(model, data, previous = 0):Int;
Crc.crc1(data, previous = 0):Int;
```

The registered 13 variants and parameters are:

| Variant | Width | Polynomial | Init | RefIn | RefOut | XorOut |
| --- | ---: | ---: | ---: | :---: | :---: | ---: |
| CRC-8 | 8 | 07 | 00 | no | no | 00 |
| CRC-8/1-WIRE | 8 | 31 | 00 | yes | yes | 00 |
| CRC-8/DVB-S2 | 8 | D5 | 00 | no | no | 00 |
| CRC-16/IBM | 16 | 8005 | 0000 | yes | yes | 0000 |
| CRC-16/CCITT-FALSE | 16 | 1021 | FFFF | no | no | 0000 |
| CRC-16/MODBUS | 16 | 8005 | FFFF | yes | yes | 0000 |
| CRC-16/KERMIT | 16 | 1021 | 0000 | yes | yes | 0000 |
| CRC-16/XMODEM | 16 | 1021 | 0000 | no | no | 0000 |
| CRC-24 | 24 | 864CFB | B704CE | no | no | 000000 |
| CRC-32/IEEE | 32 | 04C11DB7 | FFFFFFFF | yes | yes | FFFFFFFF |
| CRC-32/MPEG-2 | 32 | 04C11DB7 | FFFFFFFF | no | no | 00000000 |
| CRC-32/JAMCRC | 32 | 04C11DB7 | FFFFFFFF | yes | yes | 00000000 |
| CRC-1 | 1 | special | 0 | special | special | 0 |

The first twelve rows use the reflected or direct bitwise algorithm selected
by `refin`; `refout` controls final reflection when it differs from
`refin`. Results are masked to the declared width. CRC-1 is deliberately the
byte-sum special case, reduced modulo 256 by the implementation's compatibility
contract (it is not a polynomial width-one implementation).

## Incremental semantics

A non-zero `previous` is the finalized result of an earlier call. `hash`
unfinalizes it, processes the new bytes, then finalizes the combined result.
`previous = 0` is the reset boundary and starts from `model.init`; therefore a
literal zero cannot represent a non-zero intermediate state, and callers that
need to distinguish reset from a zero result must retain that state separately.
The same rule applies to `crc1`, whose `previous` is the running byte sum.

## Verification

Vectors and incremental checks are anchored against the user-specified CRC
library and independently checked against `hash-wasm`. The suite covers empty
input, `abc`, byte ranges, all registered variants, and split updates including
the reset boundary.
