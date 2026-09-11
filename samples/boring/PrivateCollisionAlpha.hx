package boring;

#if swift_output
private class PrivateCollisionValue {
    public final label:String;

    public function new(label:String) {
        this.label = label;
    }
}

/**
    A module-private type stays file-scoped in Swift. Two modules may each
    declare a private type of the same name; emitting both as public makes
    every bare reference ambiguous.
*/
class PrivateCollisionAlpha {
    static function make():PrivateCollisionValue {
        return new PrivateCollisionValue("alpha");
    }

    public static function label():String {
        return make().label;
    }
}
#else
class PrivateCollisionAlpha {}
#end
