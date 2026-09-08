package boring;

class StaticFnOps {
    public static var transform:Int->Int = function(value:Int):Int {
        return value + 1;
    };

    public static var count:Int = 0;

    public static function apply(value:Int):Int {
        return transform(value);
    }

    public static function increment():Int {
        count += 1;
        return count;
    }
}
