# Opcode and bytecode reference

## 1. Encoding

Bytecode is little-endian. Each instruction begins with one opcode byte followed by fixed-width operands. U16 and U32 are unsigned little-endian. S32 is a signed two's-complement offset from the first byte after the instruction.

The file header is 16 bytes: magic BEP0, major U16, minor U16, feature bits U32, and total size U32. Section entries are kind U16, flags U16, offset U32, and size U32. Sections are sorted, non-overlapping, and bounded by total size.

## 2. Opcode table

| Value | Opcode | Operands | Stack input | Stack output | Allocation |
| --- | --- | --- | --- | --- | --- |
| 0x01 | CONST | U16 constant | none | constant type | no |
| 0x02 | POP | none | T | none | no |
| 0x03 | DUP | none | T | T,T | no |
| 0x04 | LOAD_LOCAL | U16 local | none | local type | no |
| 0x05 | STORE_LOCAL | U16 local | T | none | no |
| 0x06 | LOAD_CAPTURE | U16 capture | none | capture type | no |
| 0x07 | STORE_CAPTURE | U16 capture | T | none | no |
| 0x08 | LOAD_MODULE | U16 export | none | export type | no |
| 0x09 | STORE_MODULE | U16 export | T | none | no |
| 0x0a | GET_FIELD | U16 field | receiver | field type | no |
| 0x0b | SET_FIELD | U16 field | receiver,value | none | no |
| 0x0c | MAKE_ARRAY | U16 count | T repeated | Array<T> | yes |
| 0x0d | MAKE_MAP | U16 count | K,V repeated | Map<K,V> | yes |
| 0x0e | GET_INDEX | none | Sequence<T>,Int | Option<T> | no |
| 0x0f | SET_INDEX | none | Sequence<T>,Int,T | Result<Unit,BoundsError> | no |
| 0x10 | ADD | none | Int,Int or Float,Float | same type | no |
| 0x11 | SUB | none | Int,Int or Float,Float | same type | no |
| 0x12 | MUL | none | Int,Int or Float,Float | same type | no |
| 0x13 | DIV | none | Int,Int or Float,Float | same type | no |
| 0x14 | MOD | none | Int,Int | Int | no |
| 0x15 | SHL | none | Int,Int | Int | no |
| 0x16 | SHR | none | Int,Int | Int | no |
| 0x17 | EQ | none | T,T where T:Eq | Bool | no |
| 0x18 | LT | none | T,T where T:Ord | Bool | no |
| 0x19 | NOT | none | Bool | Bool | no |
| 0x1a | NEG | none | Int or Float | same type | no |
| 0x1b | JUMP | S32 | none | none | no |
| 0x1c | JUMP_IF_FALSE | S32 | Bool | none | no |
| 0x1d | JUMP_IF_NONE | S32 | Option<T> | Option<T> | no |
| 0x1e | CALL_DIRECT | U16 function,U8 argc | receiver,args | result | maybe |
| 0x1f | CALL_VIRTUAL | U16 signature,U8 argc | receiver,args | result | maybe |
| 0x20 | CALL_SUPER | U16 signature,U8 argc | receiver,args | result | maybe |
| 0x21 | MAKE_CLOSURE | U16 function,U8 captures | captures | function | yes |
| 0x22 | MAKE_ENUM | U16 case,U8 payloads | payloads | enum | yes |
| 0x23 | MATCH_TAG | U16 case | enum | Bool | no |
| 0x24 | PROPAGATE_RESULT | none | Result<T,E> | T or terminal | no |
| 0x25 | RETURN | none | result | none | no |
| 0x26 | PANIC | none | String | none | no |

Opcode 0x00 and 0x27 through 0xff are reserved and rejected. Arithmetic follows 04-errors-and-library.md. Call metadata supplies receiver, labels, parameters, result, and generic substitution. GET_INDEX and SET_INDEX carry a verified Sequence witness and element type.

## 3. Verification

The verifier tracks operand types and initialized locals. Branch targets begin instructions. Joins require equal stack height and compatible types. Calls match signatures, field operations match layouts, captures match descriptors, and RETURN matches the function result. Every allocation instruction has a safepoint bitmap listing object-valued stack and local slots.

The verifier checks header, version, feature bits, sections, UTF-8, constants, ids, nominal graph, layouts, methods, witnesses, instruction boundaries, stack underflow, local initialization, operand types, branches, return state, source maps, and limits. Any failure returns InvalidBytecode(section, offset) before module installation.

## 4. Metadata and tests

Constants use tags Bool U8, Byte U8, Int S64, Float U64 bits, String U32 length plus UTF-8 bytes, and Type U32 descriptor id. Function records contain code range, signature id, local count, capture count, max stack, source-map id, and safepoint bitmap. Class records contain base id, field range, method range, witness range, and foreign flag.

Mutations cover truncated operands, invalid/reserved opcode, section overlap, bad constant tag, invalid UTF-8, stack underflow, wrong operand type, uninitialized local, incompatible join, branch into operand, bad signature, invalid field offset, capture mismatch, bad enum payload, missing root bitmap, invalid return, and size overflow. Every mutation leaves the module table unchanged.
