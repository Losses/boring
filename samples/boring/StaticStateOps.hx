package boring;

// Mutable and container static state in the shapes the engine port test
// infrastructure consumes: a nullable static var read and assigned from its
// own class and from another class, a static final array built by mutation,
// and a static final scalar.

class StaticStateClient {
    public function new() {}

    public static function install(value:String):Void {
        StaticStateOps.current = value;
    }
}

class StaticStateOps {
    public static var current:Null<String> = null;

    private static final sections:Array<String> = [];

    public static final limit:Int = 4096;

    public static final emptyMark:String = "empty";

    public static function setCurrent(value:String):Void {
        current = value;
    }

    public static function readCurrent():String {
        final value = current;
        return value == null ? "none" : value;
    }

    public static function record(section:String):Void {
        sections.push(section);
    }

    public static function sectionCount():Int {
        return sections.length;
    }

    public static function firstSection():String {
        if (sections.length == 0) {
            return emptyMark;
        }
        return sections[0];
    }
}
