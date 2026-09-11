package boring;

#if swift_output
/**
    A coalescing default that calls `String.substring` with two indices.
    Swift String has no two-index substring overload, so the sanctioned
    default must lower through the UTF-16 helper like the expression path.
*/
class SubstringDefaultOps {
    public final text:String;
    public final part:String;

    public function new(text:String, ?part:Null<String>) {
        this.text = text;
        this.part = part == null ? text.substring(1, 3) : part;
    }

    public static function derive(text:String):String {
        return new SubstringDefaultOps(text).part;
    }
}
#else
class SubstringDefaultOps {}
#end
