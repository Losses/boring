package boring;

// A constructor whose optional nullable parameters are assigned to fields
// with different names (mirrors PunctuationAtomBuilder). The Dart
// constructor must render the optional params in the optional positional
// group so a zero-argument construction compiles.

class OptionalCtorHolder {
    public final label:String;
    public final count:Int;

    public function new(?label:Null<String>, ?count:Null<Int>) {
        this.label = label == null ? "default" : label;
        this.count = count == null ? 7 : count;
    }
}

class OptionalCtorOps {
    public static function render():String {
        final a = new OptionalCtorHolder();
        final b = new OptionalCtorHolder("x", 3);
        return a.label + "/" + a.count + "|" + b.label + "/" + b.count;
    }
}