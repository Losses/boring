package boring;

#if rust_output
/**
    A conditional declares a nullable interface while one arm constructs a
    concrete implementor and the other arm is null. The result slot carries
    `Option<Box<dyn Trait>>`, so the concrete arm boxes inside its `Some`.
*/
interface NullableBranchChoice {
    function label():String;
}

class NullableBranchAlpha implements NullableBranchChoice {
    public function new() {}

    public function label():String {
        return "alpha";
    }
}

class NullableInterfaceBranchOps {
    public static function choose(flag:Bool):Null<NullableBranchChoice> {
        final selected:Null<NullableBranchChoice> = flag ? new NullableBranchAlpha() : null;
        return selected;
    }

    public static function label(flag:Bool):String {
        final selected = choose(flag);
        return selected == null ? "none" : selected.label();
    }

    public static function assign(flag:Bool):String {
        var selected:Null<NullableBranchChoice> = null;
        if (flag) {
            selected = new NullableBranchAlpha();
        }
        return selected == null ? "none" : selected.label();
    }
}
#else
class NullableInterfaceBranchOps {}
#end
