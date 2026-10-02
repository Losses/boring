// Native harness of the dc-fs-missing probe (Dart target).
//
// It calls the generated library's entry, so every observation line comes
// from the generated tree. It catches nothing: whether the host failure
// reaches the generated catch clause is the measurement.
//
// The import path follows the layout the generator writes (the generated
// module sits under lib/, the runtime beside the package root):
//   <run>/harness.dart  ->  lib/fsprobe/fs_probe.dart
import 'lib/fsprobe/fs_probe.dart' as fsprobe;

void main() {
  fsprobe.run();
}
