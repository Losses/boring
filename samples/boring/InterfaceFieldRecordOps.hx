package boring;

#if swift_output
/**
    A typedef record with an interface-typed field. Swift cannot synthesize
    `Equatable` for a struct whose field is a protocol existential, so the
    generated struct drops the conformance.
*/
typedef InterfaceFieldRecord = {
    var label:String;
    var mark:InterfaceMark;
}

interface InterfaceMark {
    function tag():String;
}

class InterfaceMarkValue implements InterfaceMark {
    public function new() {}

    public function tag():String
        return "mark";
}

class InterfaceFieldRecordOps {
    public static function make(label:String):InterfaceFieldRecord {
        return {label: label, mark: new InterfaceMarkValue()};
    }

    public static function describe(r:InterfaceFieldRecord):String {
        return r.label + ":" + r.mark.tag();
    }
}
#else
class InterfaceFieldRecordOps {}
#end
