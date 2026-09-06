package boring;

class InstanceDefaultsTool {
    public var level:Int = 3;

    public function new() {}
}

class InstanceDefaults {
    public var count:Int = 0;
    public var label:String = "none";
    public final ratio:Float = 1.0;
    public var ready:Bool = false;
    public var tool:InstanceDefaultsTool = new InstanceDefaultsTool();
    public var plain:Int;

    public function new() {
        plain = 7;
    }
}

class InstanceDefaultsNoCtor {
    public var v:Int = 5;
    public var tag:String = "auto";
}
