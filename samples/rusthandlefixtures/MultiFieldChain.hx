package rusthandlefixtures;

// multi-field chained expression: one owned handle param is borrowed for many
// field reads inside a single result-construction expression, mimicking the
// tiqian line_adjustment_stage.rs:899 LayoutResult::new giant call where the
// handle is implicitly copied across borrow().field.clone() chains.
class Source {
    public final a:Int;
    public final b:Int;
    public final label:String;
    public function new(a:Int, b:Int, label:String) {
        this.a = a;
        this.b = b;
        this.label = label;
    }
}

class MultiFieldChainOps {
    public static function combine(source:Source):String {
        return source.label + ":" + source.a + ":" + source.b;
    }
}
