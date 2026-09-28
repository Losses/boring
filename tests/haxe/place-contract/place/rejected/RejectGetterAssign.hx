package place.rejected;

/**
	Rejected form: a store into a getter-only property. `items` declares
	`(get, never)`, so the property has no setter and the store must be
	rejected by the Haxe type checker. The file compiles alone; the
	recorded outcome is the compiler diagnostic.
**/
class RejectGetterAssign {
	static function main():Void {
		final shelf = new Shelf([10, 20]);
		shelf.items = [30, 40];
	}
}

class Shelf {
	public var backing:Array<Int>;
	public var items(get, never):Array<Int>;

	public function new(items:Array<Int>) {
		backing = items;
	}

	function get_items():Array<Int> {
		return backing;
	}
}
