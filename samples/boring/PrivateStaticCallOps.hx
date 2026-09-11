package boring;

// Cross-library consumer of a private static referenced by class name
// (mirrors the test file calling LineCandidate.emptyHanging). The Dart
// declaration lowers the private static under its `_`-prefixed name; the
// cross-library reference must match.

class PrivateStaticCallOps {
    public static function render():String {
        return PrivateStaticCallHolder.make().value;
    }
}