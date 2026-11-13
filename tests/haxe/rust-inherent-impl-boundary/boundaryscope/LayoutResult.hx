package boundaryscope;

/**
    A `:dataClass` value type. Its Rust face is a local struct, so an inherent
    impl is legal here — which is what makes the E0592 shape reachable.
    (ExtensionNameCollision)
**/
@:dataClass
class LayoutResult {
    public final clusters:Array<Int>;

    public function new(clusters:Array<Int>) {
        this.clusters = clusters;
    }
}
