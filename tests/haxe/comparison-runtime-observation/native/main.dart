// Native invocation harness for the Dart generated tree of the comparison
// observation fixture. The runner copies this file into its run directory next
// to the generated tree, so the relative import reaches
// <run>/dart-gen/lib/comparison/comparison_observe.dart. The harness prints
// the text one generated observation function returns; it holds no ordering
// decision and re-implements no comparator. The case name is the first
// argument the entry receives.
import 'dart:io';

import '../dart-gen/lib/comparison/comparison_observe.dart' as observe;

String observation(String name) {
  switch (name) {
    case 'int-ordinary':
      return observe.intOrdinary();
    case 'int-extremes':
      return observe.intExtremes();
    case 'array-order':
      return observe.arrayOrder();
    case 'nullable-order':
      return observe.nullableOrder();
    case 'string-order':
      return observe.stringOrder();
  }
  stderr.writeln('comparison harness: unknown case $name');
  exit(2);
}

void main(List<String> arguments) {
  stdout.writeln(observation(arguments.isEmpty ? '<none>' : arguments.first));
}
