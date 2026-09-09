package boring;

import boring.ProbeUnit;

/** Regression coverage for data-class defaults materialized in Rust. */
@:dataClass
class InlineDefaultOps {
    public final marker:Int;
    public final region:Int;
    public final count:Int;

    public function new(?marker:Null<Int>, region:Int, ?count:Null<Int>) {
        #if rust_output
        this.marker = marker == null ? ProbeUnit.ZERO_INT : marker;
        #else
        // ProbeUnit's value-type default lowering is rust-only coverage;
        // other targets use a plain literal default.
        this.marker = marker == null ? 7 : marker;
        #end
        this.region = region;
        this.count = count == null ? region : count;
    }
}
