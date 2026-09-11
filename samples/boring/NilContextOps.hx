package boring;

/** Swift needs the payload type at a bare nil branch of a conditional. */
class NilContextOps {
    public static function conditional(flag:Bool):Null<String> {
        return flag ? "present" : null;
    }

    public static function nullArgument():String {
        return choose(null);
    }

    static function choose(value:Null<String>):String {
        return value == null ? "empty" : value;
    }
}
