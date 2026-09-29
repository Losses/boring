package roalias;

/**
    The cross-boundary result record: the converted view alongside the
    holder retaining the original container's mutable alias. Mirrors the
    accepted pattern of
    tests/haxe/view-lifetime/ViewLifetimeBoundaryResult.hx.
**/
class BoundaryResult {
	public var view:std.ReadOnlyArray<Int>;
	public var holder:AliasHolder;

	public function new(view:std.ReadOnlyArray<Int>, holder:AliasHolder) {
		this.view = view;
		this.holder = holder;
	}
}
