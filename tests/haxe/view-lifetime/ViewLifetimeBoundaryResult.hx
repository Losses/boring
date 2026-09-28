class ViewLifetimeBoundaryResult {
    public var view:std.ReadOnlyArray<Int>;
    public var holder:ViewLifetimeHolder;

    public function new(view:std.ReadOnlyArray<Int>, holder:ViewLifetimeHolder) {
        this.view = view;
        this.holder = holder;
    }
}
