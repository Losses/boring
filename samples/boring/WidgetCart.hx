package boring;

class WidgetCart {
    public function new() {}
}

class WidgetLens {
    public final zoom:Int;

    public function new(?zoom:Int = 3) {
        this.zoom = zoom == null ? 3 : zoom;
    }
}
