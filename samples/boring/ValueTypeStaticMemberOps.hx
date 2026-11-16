package boring;

#if (swift_output || dart_output)
/**
    A value wrapper with static members. The samples had static value-type
    fields and operator statics, so a plain static factory and a static
    member whose body throws were never emitted; Swift rendered both as
    instance methods and dropped the throws marker on the factory.
**/
class ValueTypeStaticMemberFault extends haxe.Exception {
    public function new(message:String) {
        super(message);
    }
}

@:valueType
abstract ValueTypeStaticFace(String) from String {
    public inline function new(value:String)
        this = value;

    public static function plain(value:String):ValueTypeStaticFace
        return new ValueTypeStaticFace(value);

    public static function of(value:String):ValueTypeStaticFace {
        if (StringTools.trim(value) == "")
            throw new ValueTypeStaticMemberFault("blank");
        return new ValueTypeStaticFace(value);
    }

    public static function units(value:String):Int
        return value.length;

    public function requireText():String {
        if (this.length == 0)
            throw new ValueTypeStaticMemberFault("empty");
        return this;
    }

    public function toString():String
        return this;
}

class ValueTypeStaticMemberOps {
    public static function describe(raw:String):String {
        final face = ValueTypeStaticFace.of(raw);
        return face.requireText();
    }

    public static function plainUnits(raw:String):Int
        return ValueTypeStaticFace.units(ValueTypeStaticFace.plain(raw).toString());

    public static function rejectsBlank(raw:String):Bool {
        var rejected = false;
        try {
            ValueTypeStaticFace.of(raw);
        } catch (_:ValueTypeStaticMemberFault) {
            rejected = true;
        }
        return rejected;
    }
}
#else
class ValueTypeStaticMemberOps {}
#end
