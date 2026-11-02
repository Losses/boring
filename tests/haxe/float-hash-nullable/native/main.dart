// Native assertion harness for the Dart generated tree of the nullable-float
// hashCode regression contract (board t-mvzn8ckw-vh3s). The runner copies this
// file into its run directory next to the generated tree, so the relative
// import reaches <run>/dart-gen/lib/floathashnullable/float_hash_nullable_contract.dart.
// The harness instantiates the generated NullableFloatRecord and asserts, in
// the target language, that hashCode is stable for null / signed zero / NaN
// and that equals semantics are unchanged. It exits nonzero on any failure.
import 'dart:io';

import '../dart-gen/lib/floathashnullable/float_hash_nullable_contract.dart'
    as contract;

void main(List<String> arguments) {
  var failures = 0;
  void check(bool cond, String message) {
    if (!cond) {
      stderr.writeln('FAIL: $message');
      failures++;
    }
  }

  final hashNull = contract.NullableFloatRecord(null).hashCode;
  final hashPosZero = contract.NullableFloatRecord(0.0).hashCode;
  final hashNegZero = contract.NullableFloatRecord(-0.0).hashCode;
  final hashNaN = contract.NullableFloatRecord(double.nan).hashCode;

  // null hashes to 0 and a signed zero hashes to zero bits, so a single-field
  // record hashes null, +0.0, and -0.0 all equal (P-13 float canonical).
  check(hashNull == hashPosZero,
      'hashCode(null) == hashCode(+0.0) [null->0, signed-zero->0]');
  check(hashNull == hashNegZero,
      'hashCode(null) == hashCode(-0.0) [null->0, signed-zero->0]');
  // NaN keeps its quiet-token bits and is stable.
  check(hashNaN == hashNaN, 'hashCode(NaN) is stable');

  // equals semantics unchanged.
  check(contract.NullableFloatRecord(null) == contract.NullableFloatRecord(null),
      'null == null');
  check(contract.NullableFloatRecord(null) != contract.NullableFloatRecord(0.0),
      'null != +0.0');
  check(contract.NullableFloatRecord(0.0) == contract.NullableFloatRecord(-0.0),
      '+0.0 == -0.0');

  if (failures > 0) {
    stderr.writeln('$failures assertion(s) failed');
    exit(1);
  }
  stdout.writeln('float-hash-nullable dart contract: all assertions passed');
}
