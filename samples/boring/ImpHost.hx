package boring;

class ImpHost {
    public final widget:ImpWidget;

    public function new(?widget:Null<ImpWidget>) {
        this.widget = widget == null ? new ImpWidget() : widget;
    }
}
