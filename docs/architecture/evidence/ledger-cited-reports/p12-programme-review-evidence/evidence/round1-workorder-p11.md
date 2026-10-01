# Verbatim extract from docs/investigations/architecture-round-1.md: work order (lines 263-279), captured 2026-09-30T15:25:17Z
227decc236f28b438e465d52eed5dd017b4d2c6feba19f1eb0e5235cd77879a0  docs/investigations/architecture-round-1.md
The resulting work order is:

1. Establish explicit boundary decisions and their source/target distinctions.
   Swift array conversion remains the first investigation, with task D supplying
   legality, effect, and alias observations. Resolve any semantic decision
   required by the selected change before implementing it.
2. Prepare numeric conversion and operand-evaluation specifications independently.
   Their facts also support later string and null-flow work. Parallel reading
   and test design are possible, while each backend retains one writer.
3. Apply established evaluation facts to string operations and null proofs.
   Source domains and invalidation rules must precede helper consolidation.
4. Carry branch result and exit intent into target structure after the relevant
   flow and evaluation specifications exist. Keep target precedence policies local.

The coordinator has accepted the initial responsibility map and verification
design for planning. It has not accepted an implementation, a new semantic
ruling, or a full runtime coverage claim.

# Verbatim: P11 acceptance line from docs/investigations/architecture-round-1/x-guidance-evaluation.md (line 95)
### Accepted focused delivery and evaluation

The coordinator accepts the eight-file fixture after exact-file integration
and an independent replay. The executor's corrected attempt is
`view-cCrHOe9D` in its assigned checkout. The integration attempt is
