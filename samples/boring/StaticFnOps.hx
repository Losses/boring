package boring;

class StaticFnOps {
    public static var transform:String->String = function(value:String):String {
        return value + "!";
    };

    public static var count:Int = 0;

    public static function apply(value:String):String {
        return transform(value);
    }

    public static function increment():Int {
        count += 1;
        return count;
    }
}
