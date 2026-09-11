package boring;

#if swift_output
/**
    A ternary whose arms are concrete implementations of the interface it
    unified on: Swift needs each arm widened to the protocol existential.
*/
interface Breaker {
    function label():String;
}

class AlphaBreaker implements Breaker {
    public function new() {}

    public function label():String
        return "alpha";
}

class BetaBreaker implements Breaker {
    public function new() {}

    public function label():String
        return "beta";
}

class TernaryInterfaceOps {
    public static function choose(n:Int):Breaker {
        return n == 0 ? new AlphaBreaker() : new BetaBreaker();
    }

    public static function label(n:Int):String
        return choose(n).label();
}
#else
class TernaryInterfaceOps {}
#end
