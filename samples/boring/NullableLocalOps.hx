package boring;

enum LocalProbe {
    Alpha;
    Beta;
}

class NullableLocalOps {
    public static function intLocalMatches(value:Array<Null<Int>>):Bool {
        final one:Null<Int> = 1;
        return value[0] == one;
    }

    public static function floatLocalMatches(value:Array<Null<Float>>):Bool {
        final half:Null<Float> = 0.5;
        return value[0] == half;
    }

    public static function boolLocalIsNull():Bool {
        final flag:Null<Bool> = null;
        return flag == null;
    }

    public static function stringLocalMatches(value:Array<Null<String>>):Bool {
        final tag:Null<String> = "a";
        return value[0] == tag;
    }

    public static function nullableInitPassesThrough(source:Array<Null<Int>>):Bool {
        final carried:Null<Int> = source[0];
        return carried == source[0];
    }

    public static function lookupLocalPassesThrough(mode:LocalProbe):Bool {
        final back:Null<LocalProbe> = Type.createEnum(LocalProbe, Type.enumConstructor(mode));
        return back == mode;
    }
}
