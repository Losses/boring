# Layout hang verification

This document records the verification that the two layout tests reported
as hanging pass on the current v2 tip.

## Tests

- AnnotationGeometryStageCoverageTest.bopomofoAndDecorationLeadingBlankExhaustiveBranches
- DisplayGlyphSubstitutionEngineTest.ellipsisSubstitutionRollsBackWhenCoverageCannotBeVerified

## Commands

Copy the tiqian engine-haxe sources into a task workspace, then generate and
run the Swift f32 tree:

    haxe engine-haxe/targets/swift-f32.hxml
    swiftc -emit-library -emit-module -O -wmo -module-name TiqianEngine \
      -o build/libTiqianEngine.so $(find swift-gen-f32 -name '*.swift' | sort)
    swiftc -Onone -module-name TiqianEngineTests -I build -L build \
      -lTiqianEngine -o build/test-runner \
      $(find swift-gen-f32-tests -name '*.swift' | sort)
    ./build/test-runner

## Result

On v2 tip a28c03f7 both tests return verdict pass in the results file. The
busy loop reported against v2 tip 40b6b4558 does not reproduce. The eight
commits after 40b6b4558 removed the trigger condition; the likely fix is
244beca9 (fix(swift): lower Array.remove(value) to indexOf+remove(at:)
IIFE).
