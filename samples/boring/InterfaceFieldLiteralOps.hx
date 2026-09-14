package boring;

#if rust_output
/**
    An object literal whose field declares an interface while the initializer
    constructs a concrete implementor. The field slot boxes the concrete value
    so the record field carries the declared interface type.
*/
interface LiteralMark {
    function tag():String;
}

class LiteralMarkAlpha implements LiteralMark {
    public function new() {}

    public function tag():String {
        return "alpha";
    }
}

typedef LiteralMarkRecord = {
    var label:String;
    var mark:LiteralMark;
}

class InterfaceFieldLiteralOps {
    public static function make(label:String):LiteralMarkRecord {
        return {label: label, mark: new LiteralMarkAlpha()};
    }

    public static function describe():String {
        final record = make("tone");
        return record.label + ":" + record.mark.tag();
    }
}
#else
class InterfaceFieldLiteralOps {}
#end
