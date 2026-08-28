# Design principles for translation rulings

## Scope

Every specification in this directory states rulings. This document states
the principles a ruling must satisfy before it enters any specification. The
principles exist because a ruling can pass the four judgment axes and still
be wrong: it can solve a cross-target divergence by banning the divergent
operation and leaving nothing in its place, and the ban reads as cheap on
every axis. The string index ruling of 2026-08-28
(`features/08-strings-and-unicode.md`, ASCII-bounded access with no
replacement API) was that kind of error, found by review. These principles
are the written form of that review, and they bind every ruling in this
directory.

## Principles

1. **Content-defined semantics.** The meaning of an operation is defined
   over the values it operates on (for strings, the sequence of Unicode
   code points), never over the storage of one platform (UTF-16 code
   units, UTF-8 bytes). Platform storage may decide which cost tier an
   implementation runs in; it never decides what a result means.

2. **Restrict and provide in one change.** When a ruling restricts a
   general operation to a subdomain, the same specification, in the same
   change, names the sanctioned path for the general case. A restriction
   without a provided replacement is a defect in the ruling, whatever its
   performance numbers say.

3. **Cost tiers reach their floor.** Each usage pattern gets an operation
   at its inherent cost: questions every platform answers in constant time
   stay constant time; one-shot queries cost one linear pass and no
   allocation; repeated positional access gets a decode-once form followed
   by constant-time indexing. No hot path emulates another platform's
   storage.

4. **Transpiler effort is not a design input.** A ruling justifies itself
   by semantics, by domain need, or by runtime cost. Implementation
   convenience of the compiler or of any single target is not a
   justification. The test: if the alternative cost nothing to implement,
   the ruling must still stand; a ruling that falls under that hypothesis
   is redesigned in the same review.

5. **The stage-one oracle verifies, it does not define.** When the native
   behavior of the JavaScript oracle conflicts with content-defined
   semantics, the specification defines the content semantics and the
   oracle side aligns through a common-layer rewrite (the existing
   default-argument and idiom rewrites are precedents), or the divergence
   is recorded with a reason that cites one of the other principles.

## Application

Every new ruling and every change to an existing ruling states which
principles it exercises. Reviews and audits run four tests over the
specification set:

- **T1 provision**: for each banned or restricted construct, a sanctioned
  path exists for the legitimate need it blocks.
- **T2 content**: no operation's meaning is defined by a platform's
  storage or by the oracle's incidental behavior.
- **T3 cost symmetry**: no ruling imposes emulation, transcoding, or a
  higher complexity class on one target without a reason naming the
  principle that requires it.
- **T4 motive**: with implementation cost zeroed, every ruling still
  stands.

A ruling that fails a test is redesigned or reverted. A specification text
that justifies itself by implementation effort is rewritten regardless of
its other merits.
