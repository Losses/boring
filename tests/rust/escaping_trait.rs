//! Live reproduction of the EscapingTraitImplFailClosed dead path:
//! direct calls on the concrete handle keep working, while a call
//! dispatched through the @:sharedHandle slot reaches the struct trait
//! impl whose body is the fail-closed panic.

use boring_codec_gen::boring::EscapingTraitIdentityOps;

#[test]
fn path_a_concrete_handle_stays_correct() {
    assert_eq!("a:a:host", EscapingTraitIdentityOps::escaping_trait_identity_ops_concrete_direct_a().to_string());
}

#[test]
fn path_b_concrete_handle_stays_correct() {
    assert_eq!("host", EscapingTraitIdentityOps::escaping_trait_identity_ops_concrete_direct_b().to_string());
}

#[test]
fn path_c_concrete_handle_stays_correct() {
    assert_eq!("c-c:host|c-a:host", EscapingTraitIdentityOps::escaping_trait_identity_ops_concrete_direct_c().to_string());
}

#[test]
#[should_panic(expected = "requires handle identity")]
fn path_a_trait_object_reaches_fail_closed_panic() {
    let _ = EscapingTraitIdentityOps::escaping_trait_identity_ops_through_sink_a();
}

#[test]
#[should_panic(expected = "requires handle identity")]
fn path_b_trait_object_reaches_fail_closed_panic() {
    let _ = EscapingTraitIdentityOps::escaping_trait_identity_ops_through_sink_b();
}

#[test]
#[should_panic(expected = "requires handle identity")]
fn path_c_trait_object_reaches_fail_closed_panic() {
    let _ = EscapingTraitIdentityOps::escaping_trait_identity_ops_through_sink_c();
}
