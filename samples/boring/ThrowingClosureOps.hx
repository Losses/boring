package boring;

#if swift_output
import std.UStringException;
import std.UStringFault;

/**
    A zero-argument `Void` callback can carry a throwing body. Its emitted
    parameter type must admit the throw (`() throws -> Void`), a call
    through the callback makes the caller throwing, and the closure
    literal itself declares `throws`.
*/
class ThrowingClosureOps {
    public static function apply(block:() -> Void):Void {
        block();
    }

    public static function caught(block:() -> Void):Int {
        final value = try {
            block();
            0;
        } catch (error:UStringException) {
            1;
        };
        return value;
    }
}
#else
class ThrowingClosureOps {}
#end
