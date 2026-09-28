package place.rejected;

/**
	Rejected form: replacing a `final` field binding. The element store
	through the same binding stays accepted and belongs to the accepted
	observation program.
**/
class RejectFinalFieldAssign {
	static function main():Void {
		final bucket = new Bucket([30, 40]);
		bucket.items = [50, 60];
	}
}

class Bucket {
	public final items:Array<Int>;

	public function new(items:Array<Int>) {
		this.items = items;
	}
}
