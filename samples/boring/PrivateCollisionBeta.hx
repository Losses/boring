package boring;

#if swift_output
private class PrivateCollisionValue {
    public final label:String;

    public function new(label:String) {
        this.label = label;
    }
}

class PrivateCollisionBeta {
    static function make():PrivateCollisionValue {
        return new PrivateCollisionValue("beta");
    }

    public static function label():String {
        return make().label;
    }
}
#else
class PrivateCollisionBeta {}
#end
