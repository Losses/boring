package boring;

class DartLocalNameFixOps {
    public static function localShadow():String {
        final text = "value";
#if dart_output
        {
            final text = text + "!";
            return text;
        }
#else
        return text + "!";
#end
    }
}
