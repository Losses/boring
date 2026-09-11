package boring;

#if swift_output
/**
    A narrowed nullable value used as a member receiver: the `startsWith`
    lowering calls a String method and the `Math` predicates lower onto
    `Double` members, so both receivers unwrap when optional.
*/
class OptionalMemberOps {
    public static function prefix(text:Null<String>):Bool {
        if (text == null)
            return false;
        return StringTools.startsWith(text, "a");
    }

    public static function notNaN(value:Null<Float>):Bool {
        if (value == null)
            return false;
        return !Math.isNaN(value);
    }

    public static function finite(value:Null<Float>):Bool {
        return value != null && Math.isFinite(value);
    }
}
#else
class OptionalMemberOps {}
#end
