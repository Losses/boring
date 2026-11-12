//! Trait-object parity for the EscapingTraitIdentityOps fixture: a call
//! dispatched through the @:sharedHandle slot reaches the gated
//! implementor's C__HandleAdapter, which delegates on the stored handle,
//! so the trait-object path reads exactly what the concrete-handle path
//! reads. (TraitIdentityAdapter)

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
fn path_a_trait_object_matches_concrete() {
    assert_eq!("a:a:host", EscapingTraitIdentityOps::escaping_trait_identity_ops_through_sink_a().to_string());
}

#[test]
fn path_b_trait_object_matches_concrete() {
    assert_eq!("host", EscapingTraitIdentityOps::escaping_trait_identity_ops_through_sink_b().to_string());
}

#[test]
fn path_c_trait_object_matches_concrete() {
    assert_eq!("c-c:host|c-a:host", EscapingTraitIdentityOps::escaping_trait_identity_ops_through_sink_c().to_string());
}
