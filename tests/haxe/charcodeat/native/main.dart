// Dart native harness. The runner copies this file into the generated
// package at lib/charcodeat/zz_run.dart and executes it with
// `dart run` (the fuse evidence mount does not keep an executable bit,
// so no `dart compile exe` artifact is executed). The text() parameter
// is Object? so the harness compiles whether the generated codeInt()
// signature is int or int?; a null value is rendered as the token
// "null".
import "char_code_at_oracle.dart" as ro;

String text(Object? v) => v == null ? "null" : v.toString();

void main() {
  print("subRev=${ro.subRev()}");
  print("subHigh=${ro.subHigh()}");
  print("subNeg=${ro.subNeg()}");
  print("codeNull=${text(ro.codeNull())}");
  print("codeNeg=${text(ro.codeNeg())}");
  print("codeInt=${text(ro.codeInt())}");
}
