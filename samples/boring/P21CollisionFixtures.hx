package boring;

// P-21 collision-resolution fixtures (Kotlin realization, property accessor
// against explicit method). Each class pairs a field with an explicit getX/
// setX method whose Kotlin accessor would otherwise clash.

class P21StaticGetter {
    public function new() {}

    public static var name:Null<String> = null;

    public static function getName():String { return name == null ? "none" : name; }
}

class P21InstanceAccessor {
    public function new() {}

    public var value:Int = 0;

    public function setValue(v:Int):Void { value = v; }

    public function getValue():Int { return value; }
}

class P21Bidirectional {
    public function new() {}

    public var x:Int = 0;

    public function getX():Int { return x; }

    public function setX(v:Int):Void { x = v; }
}

class P21NoExplicitAccessor {
    public function new() {}

    public var y:Int = 0;
}

class P21MultipleCollisions {
    public function new() {}

    public var alpha:Int = 0;
    public var beta:Int = 0;

    public function setAlpha(v:Int):Void { alpha = v; }

    public function getBeta():Int { return beta; }
}

class P21FixtureHub {
    public function new() {}

    public function touch():Int {
        P21StaticGetter.name = "a";
        final a = P21StaticGetter.getName();
        final inst = new P21InstanceAccessor();
        inst.setValue(3);
        final c = inst.getValue();
        final bd = new P21Bidirectional();
        bd.setX(5);
        final e = bd.getX();
        final plain = new P21NoExplicitAccessor();
        plain.y = 1;
        final multi = new P21MultipleCollisions();
        multi.setAlpha(1);
        final h = multi.getBeta();
        return a.length + inst.value + c + bd.x + e + plain.y + multi.alpha + multi.beta + h;
    }
}
