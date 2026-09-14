package boring;

#if rust_output
// A Void local function whose body throws, mirroring the
// WidthIndependentAnnotationCache registerInlineObjectBoundary closure.
// The Rust lowering emitted the closure as Arc<dyn Fn(..) -> ()>, but the
// throw needs the closure's own Result boundary so each call propagates
// the enclosing fault and the unit return type stays satisfied.
class FallibleLocalFunctionOps {
    public static function guard(value:Int, limit:Int):Int {
        function check(candidate:Int):Void {
            if (candidate > limit) {
                throw new FallibleLocalFunctionFault("over limit");
            }
        }
        check(value);
        return value;
    }
}

class FallibleLocalFunctionFault extends haxe.Exception {
    public function new(message:String) {
        super(message);
    }
}
#else
class FallibleLocalFunctionOps {}
#end
