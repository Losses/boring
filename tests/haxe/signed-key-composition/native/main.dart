// Native invocation harness for the Dart generated tree of the signed key
// composition fixture. The runner copies this file into its run directory
// next to the generated tree, so the relative import reaches
// <run>/dart-gen/lib/composition/key_composition_observe.dart. The harness
// prints the text one generated observation function returns; it holds no
// ordering decision and re-implements no comparator. The case name is the
// first argument the entry receives.
import 'dart:io';

import '../dart-gen/lib/composition/key_composition_observe.dart' as observe;

String observation(String name) {
  switch (name) {
    case 'direct-int':
      return observe.directInt();
    case 'direct-int-extremes':
      return observe.directIntExtremes();
    case 'typedef-int':
      return observe.typedefInt();
    case 'typedef-int-extremes':
      return observe.typedefIntExtremes();
    case 'composite-nullable':
      return observe.compositeNullable();
    case 'composite-extremes':
      return observe.compositeExtremes();
  }
  stderr.writeln('signed-key-composition harness: unknown case $name');
  exit(2);
}

void main(List<String> arguments) {
  stdout.writeln(observation(arguments.isEmpty ? '<none>' : arguments.first));
}
