package boring;

enum SwitchMergeValue {
    First(value:Int);
    Second(value:Int);
    Third;
}

/** Exercises grouped variant switch arms with payload captures. */
class SwitchMergeOps {
    public static function grouped(value:SwitchMergeValue):String {
        return switch (value) {
            case First(payload) | Second(payload): "grouped:" + payload;
            case Third: "third";
        };
    }

    public static function single(value:SwitchMergeValue):String {
        return switch (value) {
            case First(payload): "first:" + payload;
            case Second(payload): "second:" + payload;
            case Third: "third";
        };
    }

    /** Assigns a local on every Haxe path, exposing missing generated arms. */
    public static function partial(value:SwitchMergeValue):String {
        var result:String;
        switch (value) {
            case First(payload) | Second(payload):
                result = "partial:" + payload;
            case Third:
                result = "third";
        }
        return result;
    }
}
