package boring;

#if rust_output
/**
    A captured local function that receives a String parameter holds a str
    view. Returning the view from a function whose result owns text converts
    the view once, and passing the view to another String parameter keeps the
    view unchanged.
*/
class ClosureStringViewOps {
    public static function choose(items:Array<String>, fallback:String):String {
        function pick(value:String):String {
            for (i in 0...items.length) {
                if (items[i].length > 0)
                    return items[i];
            }
            return value;
        }
        return pick(fallback);
    }

    static function wrap(value:String):String {
        return "(" + value + ")";
    }

    public static function label(value:String):String {
        function apply(v:String):String {
            return wrap(v);
        }
        return apply(value);
    }
}
#else
class ClosureStringViewOps {}
#end
