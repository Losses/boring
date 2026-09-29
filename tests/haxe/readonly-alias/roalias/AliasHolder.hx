package roalias;

/**
    A holder record retaining a mutable alias to a plain container across
    the boundary shape's producer return. Mirrors the accepted pattern of
    tests/haxe/view-lifetime/ViewLifetimeHolder.hx.
**/
class AliasHolder {
	public var values:Array<Int>;

	public function new(values:Array<Int>) {
		this.values = values;
	}
}
