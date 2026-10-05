// Dart native harness for the fs-failure-kinds fixture. The runner copies
// this file into the generated package at lib/fsfail/zz_run.dart.
import "dart:io";
import "fs_fail_oracle.dart" as ro;

void main() {
  final dir = Directory("out/fs-failure-kinds")..createSync(recursive: true);
  final missing = "${dir.path}/absent.txt";
  final file = File("${dir.path}/plain.txt")..writeAsStringSync("content");
  final denied = File("${dir.path}/denied.txt")..writeAsStringSync("secret");

  print("missing-read=${ro.readIdentity(missing)}");
  print("not-a-directory-read=${ro.readIdentity("${file.path}/child")}");
  print("write-over-directory=${ro.writeIdentity(dir.path)}");
  print("predicates-missing=${ro.predicatePair(missing)}");
  print("manual-catch=${ro.manualCatchIdentity()}");
  Process.runSync("chmod", ["000", denied.path]);
  print("denied-read=${ro.readIdentity(denied.path)}");
  Process.runSync("chmod", ["644", denied.path]);
}
