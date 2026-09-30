// Harness for the dc-null-guard-fallthrough probe. The Dart backend
// emits top-level functions, so the harness calls them directly and
// prints the probe result lines.
import 'dc_guard.dart' as dcguard;

void main() {
  print(dcguard.run());
}
