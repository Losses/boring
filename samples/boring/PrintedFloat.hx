package boring;

/**
 * A printed class record with binary32 scalar fields for the f32
 * oracle text (docs/specs/features/44-record-float-text-f32.md).
 */
@:dataClass
class PrintedFloat {
    public final ratio:Float;
    public final offset:Null<Float>;
    public final count:Int;

    public function new(ratio:Float, offset:Null<Float>, count:Int) {
        this.ratio = ratio;
        this.offset = offset;
        this.count = count;
    }
}
