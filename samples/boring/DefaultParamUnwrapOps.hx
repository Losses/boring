package boring;

#if swift_output
/**
    Optional parameters with a constant default render as plain Swift
    parameters. Their Haxe type still carries a Null wrapper, so value
    uses that trust the Haxe type would force-unwrap a type that is
    already plain in Swift.
*/
class DefaultParamUnwrapOps {
    public var mode:Int;
    public var flag:Bool;

    public function new(?mode:Int = 3, ?flag:Bool = true) {
        this.mode = mode;
        this.flag = flag;
    }

    public function combine(?stretch:Bool = true):Bool {
        return stretch && this.flag;
    }

    public static function use(value:Bool):Bool {
        return value;
    }

    public function forward(?stretch:Bool = true):Bool {
        return DefaultParamUnwrapOps.use(stretch);
    }
}
#else
class DefaultParamUnwrapOps {}
#end
