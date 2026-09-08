package boring;

class ProbeFaults {
    public static function note(?message:String, ?cause:haxe.Exception):String {
        return message == null ? "none" : message;
    }
}
