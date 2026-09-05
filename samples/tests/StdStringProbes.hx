package tests;

import boring.PlainLabel;

enum PayloadStringProbe {
    Payload(value:Int);
}

class OpaqueLabel {
    public final id:Int;

    public function new(id:Int) {
        this.id = id;
    }
}

class StdStringProbes {
    public static function classArray(value:Array<PlainLabel>):String {
        return Std.string(value);
    }

    public static function opaque(value:OpaqueLabel):String {
        return Std.string(value);
    }

    public static function opaqueArray(value:Array<OpaqueLabel>):String {
        return Std.string(value);
    }

    public static function payloadArray(value:Array<PayloadStringProbe>):String {
        return Std.string(value);
    }

    public static function nullableArray(value:Array<Null<Int>>):String {
        return Std.string(value);
    }

    public static function typeParameter<T>(value:T):String {
        return Std.string(value);
    }
}
