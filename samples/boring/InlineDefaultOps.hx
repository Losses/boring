package boring;

import boring.ProbeUnit;

/** Regression coverage for data-class defaults materialized in Rust. */
@:dataClass
class InlineDefaultOps {
    public final marker:Int;
    public final region:Int;
    public final count:Int;

    public function new(?marker:Null<Int>, region:Int, ?count:Null<Int>) {
        this.marker = marker == null ? ProbeUnit.ZERO_INT : marker;
        this.region = region;
        this.count = count == null ? region : count;
    }
}
