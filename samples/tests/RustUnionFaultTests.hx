package tests;

import boring.VectorError;
import boring.VectorException;
import registry.CoreException;
import registry.CoreFault;
import std.Test;

class RustUnionFaultTests {
    @:test("union faults preserve deterministic source text")
    public static function unionFaults():Void {
        var text = "direct|edge|cascade";
        Test.equals("direct|edge|cascade", text);
    }
}

private class RustUnionFaultSupport {
    public static function directBoth():Int {
        if (true)
            throw new VectorException(VectorError.BadMagic);
        throw new CoreException(CoreFault.Config("core"));
    }

    public static function vectorPath():Int {
        throw new VectorException(VectorError.UnexpectedEof);
    }

    public static function corePath():Int {
        throw new CoreException(CoreFault.Tree("tree"));
    }

    public static function throughCalls():Int {
        if (true)
            return vectorPath();
        return corePath();
    }

    public static function secondCaller():Int {
        return throughCalls();
    }
}
