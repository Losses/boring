package boring;

interface WidgetKind {
    public function kind():String;
}

class WidgetBuilder implements WidgetKind {
    public final scale:Int;
    public final bias:Int;

    public function new(?scale:Int = 1, ?bias:Int = 2) {
        final s = scale;
        final b = bias;
        this.scale = s == null ? 1 : s;
        this.bias = b == null ? 2 : b;
    }

    public function kind():String {
        return "widget";
    }
}
