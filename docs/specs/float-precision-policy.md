# Float Precision Policy

Status: **v1.0.0 draft**

| Role | Party |
| --- | --- |
| Author / owner | Executor (task t-mw549078-udvk) |
| Architecture arbitration | Astra (lingsuan gpt-6-astra, design final; implemented as written) |
| Sign-off / version | TL (captain); this draft is not normative until the TL promotes it |

## Purpose

This document is the single cross-target float-precision contract. It maps
"known source numeric semantics + target/lane + operation context" onto a
verifiable representation and conversion plan. It does **not** decide Haxe
source semantics; source numeric facts are inputs, produced upstream, the same
way SemanticFacts feeds SemanticPolicy.decide.

The executable encoding lives in packages/compiler/FloatPrecisionPolicy.hx
(types + decide/explain) and packages/compiler/FloatPrecisionValidator.hx
(enforcement skeleton, this round interface-only). The policy is a sibling of
docs/specs/target-semantic-policy.md, with its own ids: FP-n and P-n are
independent namespaces and never mix ids.

## Precision lane (v1 mixed)

v1 declares the compilation as **mixed precision**:

- Value floats take the precision lane (F32 or F64).
- Accumulator state is always binary64, regardless of lane, and must be
  narrowed exactly once when it crosses back into a Value slot.
- Wire and NumericHelper widths do not follow the lane.

If the team later switches to strict f32, the Accumulator rule changes to
ValuePrecision (accumulator width follows the lane). That change is an
explicit, versioned edit of this document and of FloatPrecisionPolicy.decide
-- it is **never a silent default**, and Accumulator never inherits Value
behavior by omission.

## Roles (FP-1 .. FP-6)

Six precision roles. Narrow and Widen are conversion plans between roles,
never roles themselves.

Each entry below carries the eight required fields: cross-target semantics,
precision role, allowed/forbidden operations, explicit conversions and
rounding points, plan fields, validator criteria, positive/negative fixtures,
and target restrictions.

### FP-1 Value

- **Cross-target semantics**: a Haxe Float value, field, parameter, return
  value, or container element. The lane decides the width: F32 lane ->
  binary32 storage, F64 lane -> binary64 storage. Computation happens at
  storage width; no hidden intermediate widening.
- **Precision role**: PrecisionRole.Value.
- **Allowed / forbidden**: arithmetic, comparison, assignment, parameter and
  return passing, container storage -- all allowed at lane width. Forbidden:
  implicit widening to f64 mid-expression; implicit narrowing on store;
  mixing widths in one expression without an explicit conversion edge.
- **Explicit conversions / rounding**: a Widen (Value f32 -> Accumulator) or
  Narrow (Accumulator -> Value f32) conversion edge at the exact boundary
  node; the rounding point is the narrowing store.
- **Plan fields**: role=Value, storageType=f32/f64 per lane, computeType=
  storageType, bitsType=u32/u64, literalSuffix per target profile, no
  conversionEdges unless an operand crosses an accumulator boundary.
- **Validator criteria**: every Value node has a resolved plan whose
  storageType matches the lane; every conversion edge in/out is a registered
  Narrow/Widen; no Value node computes at a width other than its storage
  width.
- **Fixtures**: positive -- `var x:Float = 1.5; x = x * 2.0;` under the F32
  lane resolves to Value/f32 with no conversion edges. Negative -- the same
  expression where the plan emits computeType=f64 while storageType=f32 is a
  validator failure (width mismatch).
- **Target restrictions**: Rust f32/f64; Kotlin Float/Double; TypeScript only
  under the F64 lane (`number` is binary64, the F32 lane is rejected at
  compilation start, consistent with FloatPrecision.hx).

### FP-2 Accumulator

- **Cross-target semantics**: accumulation state a policy table lists by name
  or that semantic analysis identifies as such (summing variables, running
  totals, reduction temporaries). Under v1 mixed it is always binary64,
  independent of the lane.
- **Precision role**: PrecisionRole.Accumulator.
- **Allowed / forbidden**: repeated binary64 arithmetic and intra-accumulator
  reads are allowed. Forbidden: binary32 accumulation; more than one narrowing
  on the way out; inheriting Value behavior by default (see "Precision lane").
- **Explicit conversions / rounding**: entering the accumulator is a Widen
  (Value -> Accumulator, exact); leaving is exactly one Narrow (Accumulator ->
  Value, round-to-nearest at the store). The accumulator-to-accumulator path
  has no rounding.
- **Plan fields**: role=Accumulator, storageType=f64, computeType=f64,
  bitsType=u64, accumulatorId (from the request), allowedOps, one Narrow edge
  per exit.
- **Validator criteria**: every accumulator node cites an accumulatorId;
  along def-use, exactly one Narrow edge leaves the accumulator and its target
  is a Value node; no accumulator operation runs at binary32.
- **Fixtures**: positive -- `total += v;` with `total` listed as an
  accumulator: Widen in, f64 add, no edges inside the loop. Negative --
  narrowing to f32 inside the accumulation loop is a failure (extra rounding
  point); an accumulator reaching a Value slot with no Narrow edge is a
  failure (accumulator escape).
- **Target restrictions**: Rust f64 storage even in an f32 compilation;
  Kotlin Double; TypeScript number (naturally binary64); Swift Double; Dart
  double. Strict-f32 relabeling is future work and imposes no restriction
  today.

### FP-3 Bits

- **Cross-target semantics**: unsigned integers of the matching width and
  bitcast results and NaN bit-pattern constants. Bits exist to inspect or
  construct bit patterns, never to do float arithmetic.
- **Precision role**: PrecisionRole.Bits.
- **Allowed / forbidden**: integer bitwise ops, comparisons, bitcast in/out
  at the matching width are allowed. Forbidden: float arithmetic on Bits; a
  bitcast across mismatched widths (u32 vs f64); treating a bitcast as a
  value conversion (it preserves bits and leaves the value unchanged).
- **Explicit conversions / rounding**: only the two bitcast edges,
  Value(fN) <-> Bits(uN) at the same width. A bitcast has no rounding point.
- **Plan fields**: role=Bits, storageType=u32/u64 matching the source float
  width, computeType=storageType, bitsType=storageType, the bitcast edge in
  conversionEdges, roundingPoint=none.
- **Validator criteria**: every bitcast edge pairs equal widths; a Bits node
  never carries a float arithmetic allowance.
- **Fixtures**: positive -- a f32 bit pattern round-trip under the F32 lane:
  Bits/u32 with one bitcast edge. Negative -- a u32 <-> f64 bitcast plan
  fails (width mismatch).
- **Target restrictions**: Rust u32/u64 via to_bits/from_bits; Kotlin width
  helpers per stdlib; TypeScript needs a DataView-backed helper and is
  F64-lane only.

### FP-4 Wire

- **Cross-target semantics**: protocol-fixed-width fields (wire format). The
  width is declared by the protocol and never follows the lane.
- **Precision role**: PrecisionRole.Wire.
- **Allowed / forbidden**: encode/decode at the declared width are allowed.
  Forbidden: using the lane to change wire width; arithmetic on Wire values
  without first converting to Value; implicit lane-driven re-encodings.
- **Explicit conversions / rounding**: encode (Value -> Wire) and decode
  (Wire -> Value) edges; each names its rounding behavior in the edge (a
  decode is exact, an f32 encode rounds once).
- **Plan fields**: role=Wire, storageType=protocol width (f32/f64/byte-form as
  declared), bitsType matching, conversionEdges carrying encode/decode,
  ruleIds=[FP-4].
- **Validator criteria**: wire width equals the declared protocol width on
  every target; every Value <-> Wire hop goes through the encode/decode
  edges, never a bare cast.
- **Fixtures**: positive -- a protocol field declared f32 encodes once with
  one rounding point on both targets. Negative -- a Wire slot that follows
  the F32 lane to f64 on one target and f32 on another fails (lane leaked
  into wire).
- **Target restrictions**: identical logical width on Rust/Kotlin/TypeScript/
  Swift/Dart; byte order and storage form are target realizations, not
  policy.

### FP-5 NumericHelper

- **Cross-target semantics**: parsing, formatting, and protocol helper
  functions. Each helper has its own explicit signature and never changes its
  types because a caller lane changed.
- **Precision role**: PrecisionRole.NumericHelper.
- **Allowed / forbidden**: the helper declared parse/format/encode/decode
  operations are allowed. Forbidden: retyping a helper per caller lane; a
  helper converting through the caller width implicitly; hiding a rounding
  point inside a helper without declaring it.
- **Explicit conversions / rounding**: edges are declared in the helper own
  signature; the plan records the helper declared widths and the rounding
  points it names.
- **Plan fields**: role=NumericHelper, storageType and computeType from the
  helper explicit signature, bitsType where the signature declares one,
  ruleIds=[FP-5].
- **Validator criteria**: the plan widths equal the helper declared signature;
  a caller lane never alters the helper plan.
- **Fixtures**: positive -- a parse helper declared (String) -> f64 returns
  f64 under both lanes with the same plan. Negative -- a helper whose plan
  flips storage from f64 to f32 because the caller is F32-lane fails
  (lane-sensitive helper signature).
- **Target restrictions**: helper realizations are per-target, but their
  declared widths are not.

### FP-6 IntToFloat

- **Cross-target semantics**: the Haxe Int -> Float conversion. The result is
  a Value at lane width; it is not an implicit f64 intermediate and does not
  confer any f64 semantics on the surrounding expression.
- **Precision role**: PrecisionRole.IntToFloat (the resulting node plan role
  is Value with IntToFloat provenance).
- **Allowed / forbidden**: the conversion itself is always allowed. Forbidden:
  reusing IntToFloat to justify f64 intermediates; folding Int arithmetic
  into the float plan.
- **Explicit conversions / rounding**: one IntToFloat edge; exact for 32-bit
  ints at both lane widths, so roundingPoint=none.
- **Plan fields**: role=Value, storageType per lane,
  conversionEdges=[IntToFloat], provenance names FP-6.
- **Validator criteria**: the edge exists exactly once per conversion site
  and the result plan role is Value; the surrounding expression widths stay
  lane-bound.
- **Fixtures**: positive -- `var f:Float = i;` under the F32 lane: IntToFloat
  edge, result Value/f32. Negative -- a plan claiming the result is a
  binary64 intermediate that then widens a binary32 neighbor fails (phantom
  f64).
- **Target restrictions**: TypeScript `i` is already `number` (the edge is a
  no-op annotation); Kotlin i.toDouble()/i.toFloat() per lane; Rust
  `i as f32` / `i as f64`.

## Conversion plans

Narrow and Widen are conversion plans with a source role and a destination
role. They are never roles, never freely chosen, and always appear in
plan.conversionEdges with from, to, the rounding behavior, and the citing
entry id. An unregistered conversion is a validator failure, mirroring the
P-25 fail-closed shape.

## Interface

FloatPrecisionPolicy.decide(request): PrecisionPlanResult consumes facts,
never source text: target, precisionLane (F32/F64), sourceType, operation
(literal/arithmetic/intrinsic/store/return/parse/format/encode/decode/cast),
context (Value/Accumulator/Wire/NumericHelper), destination,
accumulatorId/allowedOps, and the node id. The returned plan carries role,
storageType, computeType, bitsType, literalSuffix, conversionEdges,
roundingPoint, operationAllowance, ruleIds, provenance.
FloatPrecisionPolicy.explain(request, plan) renders a human-readable
justification citing entry ids.

## Validator

FloatPrecisionValidator scans emission-time IR together with plans. It
requires every float node to carry a source role, a destination role, and a
resolved plan; it walks def-use to check widening, narrowing, and accumulator
escape; generated-token scanning is a supplementary lint only, never the
primary authority. Rule ids FP-V-n are listed in
packages/compiler/FloatPrecisionValidator.hx.

## Relationship to SemanticPolicy

This policy runs beside SemanticPolicy, never inside it: no FP type is a
RepresentationRole variant and no FP entry cites a P-n id as its authority.
The two policies consume the same IR and may share the validator harness, but
their entry namespaces, versions, and governance stay separate.

## Scope of this round

Specification plus the policy/validator skeletons in packages/compiler/. No
emitter is wired, no backend changes, and boring.json is untouched.
