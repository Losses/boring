package tests;

import std.Test;

/**
    Probe of the target-applicability declaration (feature spec 19): one
    test applies to every target, and one declares the Swift target in
    its except argument, so Swift writes a not_applicable record for it
    while the other targets run it. The probe stands as the evidence that
    a declared exclusion stays in the cross-target id set and the
    consistency manager counts it as a declared exclusion, never a
    divergence.
**/
class TestApplicabilityProbeTests {
    @:test("a test with no except argument applies to every target")
    public static function appliesToAll():Void {
        Test.ok(true, "applies to all targets");
    }

    @:test("a test that excludes swift does not run on swift", except = ["swift"])
    public static function excludedOnSwift():Void {
        Test.ok(true, "runs on every target except swift");
    }
}
