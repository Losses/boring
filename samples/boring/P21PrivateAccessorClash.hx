package boring;

// P-21 collision-resolution fixture (Kotlin realization): a private field
// that arrives as a constructor property parameter next to an explicit
// setValue method. Kotlin forbids @JvmField on a private property, so the
// private field needs renamed JVM accessors instead of a JVM field.
class P21PrivateAccessorClash {
    public function new(value:Int) {
        this.value = value;
    }

    private var value:Int;

    public function setValue(v:Int):Void {
        value = v;
    }

    public function readValue():Int {
        return value;
    }
}

// A private final field with an explicit getter: the val has no setter to
// rename, so only the getter accessor moves aside.
class P21PrivateFinalGetterClash {
    public function new(label:String) {
        this.label = label;
    }

    final label:String;

    public function getLabel():String {
        return label;
    }
}

// A private mutable field with both explicit accessors: both synthesized
// JVM accessors move aside, so neither explicit method changes name.
class P21PrivateBothAccessors {
    public function new(count:Int) {
        this.count = count;
    }

    private var count:Int;

    public function getCount():Int {
        return count;
    }

    public function setCount(v:Int):Void {
        count = v;
    }
}
