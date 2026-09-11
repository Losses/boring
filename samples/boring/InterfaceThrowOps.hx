package boring;

#if swift_output
import std.UStringException;
import std.UStringFault;

/**
    Two classes in one module implement the same interface. Only one
    implementation throws, so only it declares `throws`; the protocol
    requirement carries `throws` because some witness does, and the call
    through the interface type picks up `try`.
*/
interface IMaybeThrow {
    function run(value:Int):Int;
}

class CleanThrower implements IMaybeThrow {
    public function new() {}

    public function run(value:Int):Int {
        return value + 1;
    }
}

class FaultyThrower implements IMaybeThrow {
    public function new() {}

    public function run(value:Int):Int {
        if (value < 0)
            throw new UStringException(UStringFault.InvalidCodePoint(1));
        return value;
    }
}

class InterfaceThrowOps {
    public static function clean():IMaybeThrow {
        return new CleanThrower();
    }

    public static function faulty():IMaybeThrow {
        return new FaultyThrower();
    }

    public static function viaInterface(impl:IMaybeThrow, value:Int):Int {
        return impl.run(value);
    }
}
#else
class InterfaceThrowOps {}
#end
