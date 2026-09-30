// Native invocation driver for the dc-promoted-eval fixture (Dart).
//
// The runner copies this file into the generated tree root, so the relative
// imports reach <tree>/lib/dcpe/eval_probe.dart and
// <tree>/lib/dcpe/double_eval_control.dart. The Dart target emits the probe as
// top-level functions and a top-level counter variable, not as a class. The
// driver only observes: it resets the probe counter, calls the probe once, and
// prints the counter. It takes no verdict; the runner compares the printed
// observation with the authored expectation.
import 'dart:io';

import 'lib/dcpe/double_eval_control.dart' as control;
import 'lib/dcpe/eval_probe.dart' as probe;

void main(List<String> arguments) {
  final requested = arguments.isEmpty ? '<none>' : arguments.first;
  switch (requested) {
    case 'promoted':
      probe.reset();
      final acc = probe.promotedOnce();
      stdout.writeln('case=promoted acc=$acc callCount=${probe.callCount}');
      break;
    case 'double':
      control.reset();
      final acc = control.doubleOnce();
      stdout.writeln('case=double acc=$acc callCount=${control.callCount}');
      break;
    default:
      stderr.writeln('dc-promoted-eval dart driver: unknown case $requested');
      exit(2);
  }
}
