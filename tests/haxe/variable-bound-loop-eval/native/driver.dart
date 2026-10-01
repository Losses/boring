// Native invocation driver for the variable-bound-loop-eval fixture (Dart).
//
// The runner copies this file into the generated tree root, so the relative
// import reaches <tree>/lib/vble/probe.dart. The Dart target emits the probe
// as top-level functions and top-level counter variables, not as a class.
// The driver only observes: it calls the three generated probe functions once
// each and prints the three returned bound-read counts. The generated main()
// calls the fixture shadow of haxe.Log (a no-op), so this driver is the only
// printer of the observation line. It takes no verdict; the runner compares
// the printed observation with the authored expectation.
import 'dart:io';

import 'lib/vble/probe.dart' as probe;

void main(List<String> arguments) {
  final local = probe.localBound();
  final length = probe.growingLength();
  final control = probe.doubleControl();
  stdout.writeln('local=$local length=$length control=$control');
}
