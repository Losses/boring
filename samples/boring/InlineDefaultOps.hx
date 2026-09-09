package boring;

import boring.ValueTypeOps.Ic;

/** Regression coverage for data-class defaults materialized in Rust. */
@:dataClass
class InlineDefaultOps {
    public final marker:Ic;
    public final region:Null<Int>;
    public final count:Null<Int>;

    public function new(?marker:Null<Ic>, ?region:Null<Int>, ?count:Null<Int>) {
        this.marker = marker == null ? Ic.ZERO : marker;
        this.region = region;
        this.count = count == null ? region : count;
    }
}
