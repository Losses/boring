package boring;

#if swift_output
/**
    `String.indexOf` lowers through `firstIndex(of:)` with a closure over
    the receiver. The receiver may itself read an enclosing local; the
    match index must therefore not be bound to a name that shadows it.
*/
class StringIndexOfShadowOps {
    public static function dashIndexAt(lines:Array<String>, i:Int):Int {
        return lines[i].indexOf("—");
    }
}
#else
class StringIndexOfShadowOps {}
#end
