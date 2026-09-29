package;

/** Regression shapes for the nullable instance-call receiver and the
    constructor optional-parameter normalization. **/
class Widget {
    public final label:String;

    public function new(label:String) {
        this.label = label;
    }

    public function tagged():String {
        return "[" + label + "]";
    }
}

class Box {
    public final label:Null<String>;

    public function new(label:String = null) {
        this.label = label;
    }

    public function hasLabel():Bool {
        return label != null;
    }
}

class ShapeFault extends haxe.Exception {
    public final detail:Null<String>;

    public function new(detail:String = null) {
        super("shape fault");
        this.detail = detail;
    }
}

class Mixer {
    public final source:String;
    public final suffix:Null<String>;

    // A required parameter first, a trailing optional nullable second,
    // and a body reassignment of the nullable parameter.
    public function new(source:String, suffix:String = null) {
        this.source = source;
        if (suffix == null) {
            suffix = source;
        }
        this.suffix = suffix;
    }

    public function suffixText():String {
        final s = suffix;
        if (s == null) {
            return source;
        }
        return source + s;
    }

    public function adoptedTagged(widget:Null<Widget>):String {
        final held = { value: widget };
        return held.value.tagged();
    }
}

class ParentFault extends haxe.Exception {
    public final code:Null<String>;

    public function new(code:String = null) {
        super("fault:" + (code == null ? "?" : code));
        this.code = code;
    }
}

class ChildFault extends ParentFault {
    public final extra:String;

    // The nullable parameter is forwarded into the parent constructor.
    // The normalization must sit before super, so the parent message sees
    // the folded null and not undefined.
    public function new(extra:String, code:String = null) {
        super(code);
        this.extra = extra;
    }
}

class NullableShapes {
    public static function tagged(widget:Widget = null):String {
        return widget.tagged();
    }

    // A guard narrows the receiver; the strict reading must not need a
    // second assertion and the receiver must evaluate once.
    public static function taggedGuarded(widget:Widget = null):String {
        if (widget == null) {
            return "none";
        }
        return widget.tagged();
    }

    // A coalesced local binds one receiver value before the call.
    public static function taggedCoalesced(a:Widget = null, b:Widget = null):String {
        final chosen = a == null ? b : a;
        return chosen.tagged();
    }

    public static function taggedAtIndex(widgets:Array<Widget>, index:Int):String {
        return widgets[index].tagged();
    }

    public static function main():Void {}
}
