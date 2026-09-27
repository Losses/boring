# ABI data layouts

## 1. Fixed representations

U8, U16, U32, U64 are unsigned fixed-width integers. S32 and S64 use two's-complement. Bool is U8 with values 0 and 1. Byte is U8. Float is an IEEE 754 binary64 bit pattern in U64. Native pointers never enter bytecode.

BeepHandle is an opaque pointer to a VM-owned root record and is valid only with its VM. BeepValue contains vm_generation U64, kind U16, flags U16, and payload U64. Object payload is a handle id, never a managed pointer. BeepTypeDesc contains descriptor id U32, kind U16, flags U16, and VM-owned reference.

## 2. Slots and outcomes

A slot array contains count U32, BeepValue entries, and parallel type descriptor ids. The VM validates count, kind, generation, and descriptor before execution. BeepOutcome contains version U16, tag U16, flags U32, BeepValue value, and record handle. Tags are Success, CompileError, RuntimeError, Panic, ResourceLimit, InvalidBytecode, and VMFault.

BeepDiagnostic contains code U32, severity U8, module handle, start/end byte offsets U32, line/column U32, message key U32, argument range, and related range. Diagnostic storage belongs to its DiagnosticSet and is released by beep_diagnostics_release.

## 3. Callback and ownership rules

Resolver receives importer name, requested path, and user data. Loader receives canonical name and returns immutable bytes, length, release callback, and user data. Allocator receives old pointer, old size, new size, and user data. Foreign callbacks receive VM, receiver handle, typed slots, count, and user data. Finalizers receive payload and user data and cannot re-enter VM.

The VM owns compiled units, module tables, handles, diagnostics, and returned records until their release operations. The host owns source bytes until loader release. Callback errors fail the compile transaction and preserve installed modules. Every API validates pointer, length, version, VM identity, thread ownership, and re-entry before reading caller memory.

## 4. ABI tests

Generate C and target declarations from one layout description. Check size, alignment, offsets, endianness, version rejection, stale handles, cross-VM values, callback lifetime, allocator retry, diagnostic release, and outcome tags on every target.
