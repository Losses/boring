// Dart native harness. The runner copies this file into the generated
// package at lib/atb/zz_run.dart and compiles it with
// `dart compile exe`.
import "container_alias_oracle.dart" as atb;

void main() {
  print("field=${atb.field()}");
  print("fieldNull=${atb.fieldNull()}");
  print("fieldRebind=${atb.fieldRebind()}");
  print("relay=${atb.relay()}");
  print("relayFresh=${atb.relayFresh()}");
}
