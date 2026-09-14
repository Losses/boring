package boring;

#if rust_output
/**
    A nullable interface field whose coalescing default names a concrete
    singleton. The unwrap_or_else closure must box the concrete value so its
    return type matches the Option of the trait object.
*/
interface BoxedShapeStyle {
    public function describe():String;
}

class FilledShapeStyle implements BoxedShapeStyle {
    public static final instance:FilledShapeStyle = new FilledShapeStyle();

    public function new() {}

    public function describe():String {
        return "filled";
    }
}

class BoxedInterfaceDefaultOps {
    public final style:BoxedShapeStyle;

    public function new(?style:Null<BoxedShapeStyle>) {
        this.style = style == null ? FilledShapeStyle.instance : style;
    }

    public function describe():String {
        return this.style.describe();
    }
}
#else
class BoxedInterfaceDefaultOps {}
#end
