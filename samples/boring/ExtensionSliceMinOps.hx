package boring;

import std.ReadOnlyArray;

#if swift_output
/**
    A marked extension function whose body slices a resident string. Inside a
    Swift extension the unqualified `min` call resolves to `Sequence.min`,
    which shadows the global function, so the emitted clamp has to name
    `Swift.min`. The samples had no extension body that slices a string.
**/
class ExtensionSliceMinOps {
    @:extension
    public static function cut(values:ReadOnlyArray<Int>, text:String, start:Int, end:Int):String
        return text.substring(start, end);
}
#else
class ExtensionSliceMinOps {}
#end
