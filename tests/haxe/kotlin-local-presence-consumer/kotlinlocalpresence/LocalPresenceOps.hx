package kotlinlocalpresence;

interface NullableTextReader {
    public function read(value:Null<String>):String;
}

interface RequiredTextRenderer {
    public function render(value:Null<LocalPresenceOps>):String;
}

class LocalPresenceOps implements NullableTextReader implements RequiredTextRenderer {
    public var label:String = "field";

    public function new(value:Null<LocalPresenceOps>) {
        if (value != null) {
            final text = value.read("constructor");
            if (text == "impossible") value.read(text);
        }
    }

    public function read(value:Null<String>):String {
        return value == null ? "missing" : value;
    }

    public function render(value:Null<LocalPresenceOps>):String {
        return value.read("override");
    }

    public static function ordinaryReturn(value:Null<LocalPresenceOps>):String {
        return value.read("ordinary");
    }

    public static function presentLocal(local:Null<LocalPresenceOps>):String {
        if (local != null) {
            return local.read("present");
        }
        return "absent";
    }

    public static function absentLocal():Null<String> {
        final local:Null<String> = null;
        return local;
    }

    public static function unknownOptional(value:Null<LocalPresenceOps>):Null<LocalPresenceOps> {
        final local:Null<LocalPresenceOps> = value;
        return local;
    }

    public static function unknownRequired(value:Null<LocalPresenceOps>):LocalPresenceOps {
        final local:LocalPresenceOps = cast(value, LocalPresenceOps);
        return local;
    }

    public static function producedConstruction():LocalPresenceOps {
        final local = new LocalPresenceOps(null);
        return local;
    }

    public static function producedCall(value:String):String {
        final local = value.toUpperCase();
        return local;
    }

    public static function producedField(value:LocalPresenceOps):String {
        final local = value.label;
        return local;
    }

    public static function nestedLiteral(value:Null<LocalPresenceOps>):String {
        final callback = function():String {
            if (value != null) return value.read("nested");
            return "absent";
        };
        return callback();
    }

    public static function nestedNameRestore():String {
        final callback = function():String {
            final after = "inner";
            return after;
        };
        final after = "outer";
        return callback() + after;
    }

    public static function defaultedNullable(?value:Null<String> = "ready"):String {
        return value.toUpperCase();
    }

    public static function unprovenNullableUppercase(value:Null<String>):Null<String> {
        return value.toUpperCase();
    }

    public static function staticEntry(value:Null<LocalPresenceOps>):String {
        if (value == null) return "absent";
        return value.read("static");
    }

    public function constructorEntry(value:Null<LocalPresenceOps>) {
        if (value != null) {
            final text = value.read("constructor");
            if (text == "impossible") value.read(text);
        }
    }

    public static function fusionLoopTrailing(value:Null<String>):String {
        var local:Null<String> = null;
        local = value;
        while (local == null) {
            local = "ready";
        }
        {
            final result = local;
            return result;
        }
    }
}
