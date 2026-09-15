package boring;

#if rust_output
/**
    A nullable String read reaching a plain &str parameter unwraps its
    Option view to the empty string, matching the null-to-zero bridge a
    nullable scalar receives.
*/
class NullableStringViewOps {
    public static function lengthOrZero(value:Null<String>):Int {
        return measure(value);
    }

    static function measure(text:String):Int {
        return text.length;
    }
}
#else
class NullableStringViewOps {}
#end
