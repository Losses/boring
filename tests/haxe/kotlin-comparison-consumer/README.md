# Kotlin source comparison consumer

Run from the repository root:

    nix develop -c bash tests/haxe/kotlin-comparison-consumer/run.sh

Each run creates a fresh out/kotlin-comparison-consumer/attempt-* directory.
input-sha256.txt fixes the source and runner inputs; generated-sha256.txt
and artifact-sha256.txt identify the generated Kotlin and executable jar.
Every stage retains its NUL separated argv, working directory, numeric exit
status, and unmodified stdout and stderr in logs/.

The macro probe asks SourceComparisonAnalysis.admit about two distinct
declarations named SameKey and a record reached through a recursive nullable
alias. The generated Kotlin functions are then compiled with the native
harness. JVM assertions exercise both same named declarations, a finite
recursive chain, and the recursive alias at runtime, the generic parameter
composition cases from the shared comparison observation, and enum ordinal
ordering through a data class with an enum stored field. expected.stdout
and expected-identity.stdout are authored independently of the generated
result.

Three negative controls follow the passing comparison. The kotlin target
carries no retired comparator plan spelling, so its registry consumer row
is satisfied by the real SourceComparisonAnalysis import and call. A data
class whose stored field rejects the sorted key request must fail
generation at the key selection boundary with the comparison diagnostic.
A generated comparator with a reversed scalar comparison must fail the JVM
check.

The parameter identity probe generates two generic records that live in
one module and share the parameter identity, and asserts at runtime that
the nested key still orders by the outer field first and the inner field
second.

This fixture covers record, integer, string, nullable record, generic
comparator parameter, and enum ordinal operations. It does not cover every
enum constructor form or full target library compilation.
