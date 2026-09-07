package tests;

import boring.SwiftLiteralSafetyOps;

class SwiftLiteralSafetyOpsTests {
    public static function main() {
        Test.equals(0.0, SwiftLiteralSafetyOps.trailingPoint());
        Test.equals("before" + String.fromCharCode(8) + "after", SwiftLiteralSafetyOps.controlText());
    }
}
