// Dart native harness. The runner copies this file into the generated
// package at lib/roalias/zz_run.dart and compiles it with
// `dart compile exe`.
import "read_only_alias_oracle.dart" as ro;

void main() {
  print("alias=${ro.alias()}");
  print("passed=${ro.passed()}");
  print("escaped=${ro.escaped()}");
  print("rebind=${ro.rebind()}");
  print("boundary=${ro.boundary()}");
}
