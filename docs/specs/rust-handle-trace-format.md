# Rust Handle Trace Format

Status: v1.0.0

| Role | Party |
| --- | --- |
| Author / owner | Executor-D |
| Sign-off / version | TL (captain) |
| Architecture arbitration | Astra (lingsuan gpt-6-astra, open-ended consultation) |

## Purpose

This document is the normative format of the machine-readable lowering trace for
the Rust handle-semantics IR (policy entry P-19 in
docs/specs/target-semantic-policy.md). The trace is target-neutral text over the
typed IR (repr / mode / identity / place_kind), never rendered Rust: a consumer
reasons about the resolved typed-IR vocabulary, not about Rust surface syntax.

The executable producer of this format is packages/compiler/RustHandleTrace.hx;
the validator (packages/compiler/RustHandleValidator.hx) and this trace share the
same typed-IR vocabulary from packages/compiler/SemanticPolicy.hx.

## Container

The trace is newline-delimited JSON (jsonl). One record per lowered expression,
in lowering order, no trailing newline between records.

    {"expr_id":"e1","repr":"Handle(tests.Counter,NonNull,plain)","mode":"HandleClone","identity":"LocalHandle","place_kind":"Local"}

Field order is canonical: expr_id, repr, mode, identity, place_kind.

## Record fields

| field | type | meaning |
| --- | --- | --- |
| expr_id | string | stable expression identity within one lowering unit |
| repr | string | serialized ReprType (see below) |
| mode | string | serialized UseMode (see below) |
| identity | string | serialized ExprIdentity (see below) |
| place_kind | string | serialized PlaceKind (see below) |

An expression with no trace record is a lowering error (P-19): the trace is
emitted for every lowered expression, including the ones the validator rejects
(their record still names the offending repr/mode/identity/place_kind).

## Field serializations

### repr (ReprType)

| ReprType | serialized form |
| --- | --- |
| Copy | Copy |
| ImmutableValue | ImmutableValue |
| Handle(class_id, nullability, shared) | Handle(<class_id>,<NonNull|Nullable>,<plain|shared>) |
| Collection(element) | Collection(<element>) |
| Nullable(inner) | Nullable(<inner>) |
| Function(args, result, mutability, captures) | Function([<args>]-><result>,<Fn|FnMut>,[<captures>]) |
| Static(inner) | Static(<inner>) |

Nested reprs serialize recursively; a function's args and captures serialize as
comma-separated lists inside brackets.

### mode (UseMode)

Owned, SharedRef, HandleClone, ReadBorrow, WriteBorrow, Move,
FunctionHandleClone, Call. An unresolved mode serializes as unresolved (the
validator reports it as a P-5 lowering error, never as a silent guess).

### identity (ExprIdentity)

SelfHandle, LocalHandle, FieldHandle, FreshObject, BorrowedProjection. A missing
identity serializes as missing (the validator reports it as a P-6 error).

### place_kind (PlaceKind)

Value, Local, Field, Index, Static. A missing place kind serializes as missing.

## Example

    {"expr_id":"e1","repr":"Handle(tests.Counter,NonNull,plain)","mode":"Owned","identity":"FreshObject","place_kind":"Value"}
    {"expr_id":"e2","repr":"Copy","mode":"Call","identity":"SelfHandle","place_kind":"Value"}
    {"expr_id":"e3","repr":"Function([Copy]->Copy,FnMut,[Handle(tests.Counter,NonNull,plain)])","mode":"Call","identity":"LocalHandle","place_kind":"Local"}

## Design principles

The trace upholds the repository design principle that the stage-one oracle
verifies rather than defines (docs/specs/design-principles.md): a trace record
reports the resolved typed-IR facts a later fingerprint/bucketing harness
consumes, and it never re-derives a representation, mode, identity, or place
kind from rendered target text.
