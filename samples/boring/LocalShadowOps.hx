package boring;

class LocalShadowOps {
    public static function arrays():Int {
        #if kotlin_output
        final first = [for (i in 0...2) i + 1];
        final second = [for (i in 0...2) i + 3];
        #else
        final first = [1, 2];
        final second = [3, 4];
        #end
        return first[0] + first[1] + second[0] + second[1];
    }

    public static function shadow():String {
        #if kotlin_output
        var tag = "a";
        var before = tag;
        var tag = "b";
        return before + tag;
        #else
        var firstTag = "a";
        var before = firstTag;
        var secondTag = "b";
        return before + secondTag;
        #end
    }

    public static function single():Int {
        var value = 41;
        return value + 1;
    }
}
