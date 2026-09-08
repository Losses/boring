package boring;

interface WidgetKind {
    public function kind():String;
}

class WidgetBuilder implements WidgetKind {
    public final scale:Int;
    public final bias:Int;

    public function new(?scale:Int = 1, ?bias:Int = 2) {
        this.scale = scale == null ? 1 : scale;
        this.bias = bias == null ? 2 : bias;
    }

    public function kind():String {
        return "widget";
    }
}
