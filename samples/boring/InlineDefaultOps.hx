package boring;

/** Regression coverage for data-class defaults materialized in Rust. */
@:dataClass
class InlineDefaultOps {
    public final marker:Int;
    public final region:Int;
    public final count:Int;

    public function new(region:Int, ?marker:Null<Int>, ?count:Null<Int>) {
        // The abstract-static-default path through ProbeUnit.ZERO_INT is
        // exercised by the ProbeUnit sample; this sample covers the plain
        // int default and the parameter-read default (count = region).
        this.marker = marker == null ? 0 : marker;
        this.region = region;
        this.count = count == null ? region : count;
    }
}
