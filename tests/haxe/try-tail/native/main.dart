// Dart native harness. The runner copies this file into the generated
// package at lib/trytail/zz_run.dart and runs it with `dart run` (AOT
// artifacts cannot execute on the dc-warn fuse mount).
import "try_tail_oracle.dart" as ro;

void main() {
  print("p1-init=${ro.p1Init()}");
  print("p1-ret=${ro.p1Ret()}");
  print("p1-handler=${ro.p1Handler()}");
  print("p2-init=${ro.p2Init()}");
  print("p2-ret=${ro.p2Ret()}");
  print("p2-handler=${ro.p2Handler()}");
  print("p3-init=${ro.p3Init()}");
  print("p3-ret=${ro.p3Ret()}");
  print("p3-handler=${ro.p3Handler()}");
  print("p4-init=${ro.p4Init()}");
  print("p4-ret=${ro.p4Ret()}");
  print("p4-handler=${ro.p4Handler()}");
}
