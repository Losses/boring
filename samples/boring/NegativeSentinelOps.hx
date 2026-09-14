package boring;

#if rust_output
/**
    A sentinel local starts at -1 and later takes a loop index. The
    underflow-prone length comparison moves the local into the signed
    domain, so its declaration and every arithmetic use share the signed
    rendering.
*/
class NegativeSentinelOps {
    public static function separatorIndex(text:String):Int {
        var separator = -1;
        for (i in 0...text.length) {
            if (text.charCodeAt(i) == 45) {
                separator = i;
                break;
            }
        }
        if (separator < 0) {
            return -1;
        }
        if (separator > 0 && separator < text.length - 1) {
            return separator;
        }
        return 0;
    }
}
#else
class NegativeSentinelOps {}
#end
