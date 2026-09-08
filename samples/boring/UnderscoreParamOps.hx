package boring;

class UnderscoreParamOps {
    #if kotlin_output
    public static function resolve(_:Int):Int {
        return _ + 1;
    }

    public static function pair(_:Int, __:Int):Int {
        return _ + __;
    }
    #else
    public static function resolve(value:Int):Int {
        return value + 1;
    }

    public static function pair(first:Int, second:Int):Int {
        return first + second;
    }
    #end
}
