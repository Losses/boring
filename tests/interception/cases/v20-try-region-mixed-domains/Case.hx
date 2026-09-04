// expect: V20 TryRegionMixedDomains
import boring.Console;
import boring.VectorException;
import std.UStringException;
import std.UStringFault;

class Case {
    static function main():Void {
        try {
            throw new UStringException(UStringFault.InvalidCodePoint(0xD800));
            Console.log("unreachable");
        } catch (error:VectorException) {
            Console.log("caught");
        }
    }
}
