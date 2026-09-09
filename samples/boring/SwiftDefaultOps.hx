package boring;

@:dataClass
class SwiftDefaultRecord {
    public final style:ProbeUnit;

    public function new(?style:Null<ProbeUnit>) {
        this.style = style == null ? ProbeUnit.ZERO : style;
    }
}

class SwiftDefaultOps {
    public static function hasDefault():Bool
        return new SwiftDefaultRecord().style == ProbeUnit.ZERO;
}
