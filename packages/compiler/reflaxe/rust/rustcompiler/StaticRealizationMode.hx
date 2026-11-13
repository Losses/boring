package rustcompiler;

/**
    The declared realization of one static/global. Every emitted static
    declares exactly one mode and RustStaticRealization.verifyItem checks
    the rendered Rust item against it.
**/
enum StaticRealizationMode {
    ImmutableLazy;
    ThreadAffine;
    ThreadSafeShared;
}
