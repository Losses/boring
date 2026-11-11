#if rust_output
package tests;

import std.Test;

/**
    Concrete-handle side of the EscapingTraitIdentityOps fixture. Direct
    calls on the concrete class stay on the NonTraitMethodFullBody path,
    so all three trigger paths keep returning correct values here. The
    trait-object side (the fail-closed panic) is asserted by the
    hand-written Rust test tests/rust/escaping_trait.rs with
    #[should_panic], because a panic aborts the test process.
*/
class EscapingTraitIdentityTests {
    @:test("path A stays correct on the concrete handle")
    public static function concretePathA():Void {
        Test.equals("a:a:host", boring.EscapingTraitIdentityOps.concreteDirectA());
    }

    @:test("path B stays correct on the concrete handle")
    public static function concretePathB():Void {
        Test.equals("host", boring.EscapingTraitIdentityOps.concreteDirectB());
    }

    @:test("path C stays correct on the concrete handle")
    public static function concretePathC():Void {
        Test.equals("c-c:host|c-a:host", boring.EscapingTraitIdentityOps.concreteDirectC());
    }
}
#end
