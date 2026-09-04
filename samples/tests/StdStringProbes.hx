package tests;

import boring.PlainLabel;

enum PayloadStringProbe {
    Payload(value:Int);
}

class StdStringProbes {
    public static function classArray(value:Array<PlainLabel>):String {
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
