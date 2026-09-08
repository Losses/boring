package boring;

class WidgetCart {
    public function new() {}
}

class WidgetLens {
    public final zoom:Int;

    public function new(?zoom:Int = 3) {
        final z = zoom;
        this.zoom = z == null ? 3 : z;
    }
}
