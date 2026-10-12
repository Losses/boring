package rustreferprobe;

/**
    Minimal resident type for the rust-refer self-test fixture
    (tests/haxe/rust-refer-unresolved). The fixture plants one phantom
    SymbolRef through rustcompiler.RustSymbols.probeRefer() and proves the
    end-of-generation reference check fails with "unresolved symbol" unless
    -D rust_refer_ablate is set. This class only exists to give the build a
    real compilation unit; it plays no role in the reference check.
**/
class RustReferProbe {
    public static var marker: Int = 0;

    public function new() {}
}
